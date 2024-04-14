#!/usr/bin/env bash

if [ -z "$1" ]; then
	echo "Usage: $0 <path-to-exported-project>"
	exit 1
fi
src=$1
if [[ ! "$src" == */ ]]; then
	src="$src/"
fi
src="$src""Assets/Resources/sheet"
dest="res/sheet"
dest_backup="res/sheet.bak"
sheets=(
	LanguageSheet
	LyricsInfoSheet
	LyricsInfoSheetCN
	LyricsSheet
	LyricsSheetCN
	SingerSheet
	SongLibSheet
	SongLibSheetCN
)
if [ -d "$dest_backup" ]; then
	rm -r "$dest_backup"
fi
if [ -d "$dest" ]; then
	mv "$dest" "$dest_backup"
fi
mkdir -p "$dest"
for f in "${sheets[@]}"; do
	src_file="$src/$f.asset"
	if [ ! -f "$src_file" ]; then
		echo "File not found: $src_file"
		exit 1
	fi
	cp "$src_file" "$dest"
done
