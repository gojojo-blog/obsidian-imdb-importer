# 🎬 IMDb Markdown Importer

A Bash script that parses your personal IMDb CSV list and enriches each entry using the OMDb API, generating well-structured Markdown files for use in Obsidian.


## Features

- Parses IMDb CSV exports with your personal ratings
- Enriches entries with:
  - Title, Year, IMDb Rating, Your Rating
  - Runtime, Genre, Cast, Director(s), Writer(s)
  - Poster and Plot Summary
- Supports both Movies and TV Shows
- For TV Shows: Aggregates directors and writers across all seasons and episodes
- Normalizes runtime into minutes or hours
- Skips entries with missing or invalid data
- Caches OMDb API responses to avoid redundant requests
- Skips writing files if the content hasn’t changed


## Output Structure

Markdown files are saved into your Obsidian vault under separate folders for movies and TV shows:

```
/Vaults/Jojo/04 - Entertainment/01 - TV/
├── 01 - TV Shows/
│   └── Breaking Bad.md
└── 02 - Movies/
    └── The Matrix.md
```

Each `.md` file contains:

- YAML frontmatter with structured metadata
- Poster preview
- Summary block with plot and IMDb link


## ⚙ Requirements

- Bash 5.1+
- `jq` (for JSON parsing)
- OMDb API Key

### Install `jq`

- **macOS:** `brew install jq`
- **Ubuntu/Debian:** `sudo apt install jq`


## Get Your OMDb API Key

1. Go to [https://www.omdbapi.com/apikey.aspx](https://www.omdbapi.com/apikey.aspx)
2. Request a **free** API key
3. Once received by email, paste it into the script under the `OMDB_API_KEY` variable


## Exporting Your IMDb Ratings

1. Visit [https://www.imdb.com/profile](https://www.imdb.com/profile)
2. Go to “Your Ratings” or any custom list
3. Click the “...” menu → Export
4. Download the `.csv` file (e.g., `ratings.csv`) and rename it to `imdb_list.csv`
5. Place the CSV in the same folder as the script


## Configuration

Open the script and edit the following variables:

```bash
CSV_FILE="imdb_list.csv"                     # Your exported IMDb CSV
OMDB_API_KEY="your_key_here"                 # Your OMDb API Key
OUTPUT_DIR="/path/to/your/obsidian/vault"    # Your Obsidian vault path
```


## Usage

Make the script executable and run it:

```bash
chmod +x imdb_import_from_csv.sh
./imdb_import_from_csv.sh
```

The script will process all titles, enrich them using the OMDb API, and create Markdown files in your Obsidian vault.


## Notes

- TV Show director/writer data is aggregated from all available seasons
- OMDb responses are cached for 30 days in `~/.omdb_cache`
- Skipped entries will be logged if metadata is missing
- You can re-run the script anytime without overwriting unchanged files


## Tested With

- **Bash**: 5.1.16(1)-release
- **macOS**: Sequoia 15.5 (Apple Silicon)
