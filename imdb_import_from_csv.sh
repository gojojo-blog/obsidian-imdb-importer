#!/bin/bash

# Tested with:
# - Bash version: 5.1.16(1)-release
# - macOS version: macOS 15.5 Sequoia (Apple Silicon)

# -----------------------------------------------------------------------------
# Script Name : imdb_import_from_csv.sh
# Description : Parses IMDb CSV exports and converts them into Markdown files
#               for Obsidian with data enriched from the OMDb API.
# Author      : Joel Plourde (joelplourde)
# Copyright   : © 2025 Joel Plourde. All rights reserved.
# License     : MIT License – See LICENSE file or https://opensource.org/licenses/MIT
# -----------------------------------------------------------------------------

# --- Configuration Section ---
# Set up paths, API keys, cache directories, and default output locations.

# CONFIGURATION -----------------------------
CSV_FILE="imdb_list.csv"  # Exported from IMDb
# Request your API Key: https://www.omdbapi.com/apikey.aspx
OMDB_API_KEY="omdb_key" # Your OMDB API Key
IS_WATCHLIST_MODE=false
# OMDb caching setup
CACHE_DIR="$HOME/.omdb_cache"
CACHE_EXPIRY_DAYS=30
mkdir -p "$CACHE_DIR"
OUTPUT_DIR="/Users/my_user/Documents/Obsidian/Vaults/Jojo/04 - Entertainment/01 - TV" # Obsidian Vault Location for the IMDb entries
# -------------------------------------------

echo "🚀 Script started using Bash version: $BASH_VERSION"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "❌ CSV file not found: $CSV_FILE"
  exit 1
fi

for arg in "$@"; do
  if [[ "$arg" == "--watchlist" ]]; then
    IS_WATCHLIST_MODE=true
  fi
done

mkdir -p "$OUTPUT_DIR"


# --- CSV Parsing and Rating Map ---
# Read the CSV and extract IMDb IDs and user ratings.
# Store them in an associative array to process later.

# Create a lookup table: imdbID → yourRating
declare -A RATING_MAP

mapfile -t csv_lines < <(tail -n +2 "$CSV_FILE")

for line in "${csv_lines[@]}"; do
  IFS=',' read -r -a fields <<< "$line"

  # Adaptive block for both Ratings and Watchlist CSV formats
  if [[ "$IS_WATCHLIST_MODE" == true ]]; then
    imdbID=$(echo "${fields[1]}" | tr -d '"') # Const is column 2 in Watchlist
    userRating=-1
  else
    imdbID=$(echo "${fields[0]}" | tr -d '"') # Const is column 1 in Ratings CSV
    userRating=$(echo "${fields[1]}" | tr -d '"')
  fi

  if [[ ! "$userRating" =~ ^[0-9]+$ ]]; then
    # echo "🔍 Skipping due to invalid rating string → Extracted: '$userRating'"
    :
  fi

  if [[ ! "$imdbID" =~ ^tt[0-9]+$ || ( "$IS_WATCHLIST_MODE" == false && ! "$userRating" =~ ^[0-9]+$ ) ]]; then
    # echo "⏭️  Skipping entry due to invalid ID or rating → ID: '$imdbID', Rating: '$userRating'"
    continue
  fi

  RATING_MAP["$imdbID"]="$userRating"
  # echo "🧾 Loaded rating $userRating for $imdbID"
done

IMDB_IDS=("${!RATING_MAP[@]}")

if [[ ${#IMDB_IDS[@]} -eq 0 ]]; then
  echo "❌ No valid IMDb IDs with ratings found."
  exit 1
fi

echo "🎬 Found ${#IMDB_IDS[@]} title(s)."

# --- Main Processing Loop ---
# For each IMDb ID with a rating, pull OMDb data and build Markdown output.

for ID in "${IMDB_IDS[@]}"; do

  CACHE_FILE="$CACHE_DIR/$ID.json"
  FETCH_NEW_DATA=true

  if [[ -f "$CACHE_FILE" ]]; then
    MODIFIED_DAYS_AGO=$(( ( $(date +%s) - $(stat -f "%m" "$CACHE_FILE") ) / 86400 ))
    if [[ "$MODIFIED_DAYS_AGO" -lt "$CACHE_EXPIRY_DAYS" ]]; then
      EXISTING_DATA=$(<"$CACHE_FILE")
      EXISTING_RATING=$(echo "$EXISTING_DATA" | jq -r '.yourRating // empty')

      if [[ "$EXISTING_RATING" == "${RATING_MAP[$ID]}" ]]; then
        DATA="$EXISTING_DATA"
        FETCH_NEW_DATA=false
      fi
    fi
  fi

  if [[ "$FETCH_NEW_DATA" == true ]]; then
    DATA=$(curl -s "https://www.omdbapi.com/?i=$ID&apikey=$OMDB_API_KEY")
    echo "$DATA" | jq --arg rating "${RATING_MAP[$ID]}" '. + {yourRating: ($rating | tonumber? // null)}' > "$CACHE_FILE"
  fi

  TITLE=$(echo "$DATA" | jq -r '.Title')
  YEAR=$(echo "$DATA" | jq -r '.Year')
  RATING=$(echo "$DATA" | jq -r '.imdbRating')
  GENRE=$(echo "$DATA" | jq -r '.Genre')
  DIRECTOR=$(echo "$DATA" | jq -r '.Director')
  WRITER=$(echo "$DATA" | jq -r '.Writer')
  ACTORS=$(echo "$DATA" | jq -r '.Actors')
  RUNTIME=$(echo "$DATA" | jq -r '.Runtime')

  # Normalize runtime: remove weird characters like 'S', strip 'min', and convert long runtimes
  RAW_RUNTIME=$(echo "$RUNTIME" | grep -oE '[0-9]+')

  if [[ -z "$RAW_RUNTIME" || "$RUNTIME" == "N/A" ]]; then
    RUNTIME=""
  elif [[ "$RAW_RUNTIME" -ge 60 ]]; then
    HOURS=$((RAW_RUNTIME / 60))
    MINS=$((RAW_RUNTIME % 60))
    if [[ $MINS -eq 0 ]]; then
      RUNTIME="${HOURS}h"
    else
      RUNTIME="${HOURS}h ${MINS}min"
    fi
  else
    RUNTIME="${RAW_RUNTIME} min"
  fi
  PLOT=$(echo "$DATA" | jq -r '.Plot')
  POSTER=$(echo "$DATA" | jq -r '.Poster')
  TYPE=$(echo "$DATA" | jq -r '.Type')

  if [[ -z "$TITLE" || "$TITLE" == "null" ]]; then
    echo "⚠️  Skipping $ID due to missing title"
    continue
  fi

  if [[ "$TYPE" == "series" ]]; then
    # --- TV Series Episode Loop ---
    # If the item is a series, iterate through each season and gather directors/writers per episode.

    TOTAL_SEASONS=$(echo "$DATA" | jq -r '.totalSeasons')
    if [[ "$TOTAL_SEASONS" =~ ^[0-9]+$ ]]; then
      ALL_DIRECTORS=()
      ALL_WRITERS=()
      for (( SEASON=1; SEASON<=TOTAL_SEASONS; SEASON++ )); do
        SEASON_DATA=$(curl -s "https://www.omdbapi.com/?i=$ID&Season=$SEASON&apikey=$OMDB_API_KEY")
        # Null check before iterating Episodes[]
        if echo "$SEASON_DATA" | jq -e '.Episodes' | grep -q null; then
          continue
        fi
        EPISODE_IDS=$(echo "$SEASON_DATA" | jq -r '.Episodes[].imdbID')
        for EP_ID in $EPISODE_IDS; do
          EP_DATA=$(curl -s "https://www.omdbapi.com/?i=$EP_ID&apikey=$OMDB_API_KEY")
          if [[ "$SEASON" == "1" && ( -z "$RUNTIME" || "$RUNTIME" == "N/A" || "$RUNTIME" =~ [^0-9[:space:]] || "$RUNTIME" -gt 180 ) ]]; then
            EP_RUNTIME=$(echo "$EP_DATA" | jq -r '.Runtime' | grep -oE '[0-9]+')
            if [[ -n "$EP_RUNTIME" && "$EP_RUNTIME" -lt 180 ]]; then
              if [[ "$EP_RUNTIME" -ge 60 ]]; then
                HOURS=$((EP_RUNTIME / 60))
                MINS=$((EP_RUNTIME % 60))
                if [[ $MINS -eq 0 ]]; then
                  RUNTIME="${HOURS}h"
                else
                  RUNTIME="${HOURS}h ${MINS}min"
                fi
              else
                RUNTIME="${EP_RUNTIME} min"
              fi
            fi
          fi
          EP_DIRECTOR=$(echo "$EP_DATA" | jq -r '.Director')
          ALL_DIRECTORS+=("$EP_DIRECTOR")
          EP_WRITER=$(echo "$EP_DATA" | jq -r '.Writer')
          ALL_WRITERS+=("$EP_WRITER")
        done
      done
      # Get unique directors, exclude N/A
      UNIQUE_DIRECTORS=$(printf "%s\n" "${ALL_DIRECTORS[@]}" | grep -v 'N/A' | sort -u | tr '\n' ',' | sed 's/,$//')
      if [[ -z "$UNIQUE_DIRECTORS" ]]; then
        DIRECTOR=$(echo "$DATA" | jq -r '.Director')
      else
        DIRECTOR="$UNIQUE_DIRECTORS"
      fi
      # Get unique writers, exclude N/A
      UNIQUE_WRITERS=$(printf "%s\n" "${ALL_WRITERS[@]}" | grep -v 'N/A' | sort -u | tr '\n' ',' | sed 's/,$//')
      if [[ -z "$UNIQUE_WRITERS" ]]; then
        WRITER=$(echo "$DATA" | jq -r '.Writer')
      else
        WRITER="$UNIQUE_WRITERS"
      fi
    fi
  fi

  YOUR_RATING="${RATING_MAP[$ID]}"
  # Attempt to preserve existing progress status from previously written files
  # Determine progress value
  if [[ -f "$FILENAME" ]]; then
    PROGRESS_VALUE=$(grep '^progress:' "$FILENAME" | sed 's/progress: "\(.*\)"/\1/')
  fi

  # Set progress status based on context:
  # - If running in watchlist mode → default to "Backlog"
  # - If user rating exists and is >= 1 → assume "Completed"
  # - Otherwise → fallback to "Backlog"
  if [[ -z "$PROGRESS_VALUE" ]]; then
    if [[ "$IS_WATCHLIST_MODE" == true ]]; then
      PROGRESS_VALUE="Backlog"
    elif [[ "$YOUR_RATING" =~ ^[0-9]+$ && "$YOUR_RATING" -ge 1 ]]; then
      PROGRESS_VALUE="Completed"
    else
      PROGRESS_VALUE="Backlog"
    fi
  fi

  SAFE_TITLE=$(echo "$TITLE" | tr '/' '_' | tr -d '":*?<>|')

  if [[ "$TYPE" == "series" ]]; then
    FINAL_OUTPUT_DIR="/Users/joelplourde/Documents/Obsidian/Vaults/Jojo/04 - Entertainment/01 - TV/01 - TV Shows"
  else
    FINAL_OUTPUT_DIR="/Users/joelplourde/Documents/Obsidian/Vaults/Jojo/04 - Entertainment/01 - TV/02 - Movies"
  fi

  mkdir -p "$FINAL_OUTPUT_DIR"

  FILENAME="${FINAL_OUTPUT_DIR}/${TITLE}.md"

  # --- Markdown File Generation ---
  # Format all retrieved data into a Markdown front matter and body.
  # Skip writing if no content has changed.

  # Always ensure progress value is written with a fallback to "Backlog" in YAML
  NEW_CONTENT=$(cat <<EOF
---
title: "$TITLE"
year: "$YEAR"
imdbID: "$ID"
imdbRating: "$RATING"
yourRating: $( [[ "$YOUR_RATING" -ge 0 ]] 2>/dev/null && echo "$YOUR_RATING" || echo "null" )
progress: "$( [[ -n "$PROGRESS_VALUE" ]] && echo "$PROGRESS_VALUE" || echo "Backlog" )"
type: "$TYPE"
runtime: "$RUNTIME"
genres: [$(echo "$GENRE" | awk -F, '{for(i=1;i<=NF;i++) printf "\"%s\", ", $i}' | sed 's/, $//')]
director: [$(echo "$DIRECTOR" | awk -F',' '{for(i=1;i<=NF;i++) printf "\"%s\", ", $i}' | sed 's/, $//')]
writer: [$(echo "$WRITER" | awk -F',' '{for(i=1;i<=NF;i++) printf "\"%s\", ", $i}' | sed 's/, $//')]
cast: [$(echo "$ACTORS" | awk -F, '{for(i=1;i<=NF;i++) printf "\"%s\", ", $i}' | sed 's/, $//')]
poster: "$POSTER"
tags: ["imdb", "$TYPE"]
---

# $TITLE ($YEAR)

![Poster]($POSTER)

**Type**: $TYPE  
**Genre**: $GENRE  
**Runtime**: $RUNTIME  
**IMDb Rating**: $RATING / 10  
**Your Rating**: $YOUR_RATING / 10  
**Director**: $DIRECTOR  
**Writer**: $WRITER  
**Cast**: $ACTORS

---

## 📝 Summary

> $PLOT

[View on IMDb](https://www.imdb.com/title/$ID/)
EOF
)

  if [[ -f "$FILENAME" ]] && echo "$NEW_CONTENT" | cmp -s - "$FILENAME"; then
    echo "⚡ No changes for $TITLE ($ID), skipping."
  else
    echo "📝 Writing file: $FILENAME"
    echo "$NEW_CONTENT" > "$FILENAME"
    echo "✅ Finished writing file for $TITLE ($ID)"
  fi
done


# --- Completion Message ---

echo "✅ Finished! Markdown files saved to: $OUTPUT_DIR"
if [[ "$IS_WATCHLIST_MODE" == true ]]; then
  echo "ℹ️  Watchlist mode enabled — Ratings were not applied."
fi
