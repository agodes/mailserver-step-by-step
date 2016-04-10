#!/bin/bash


TMPINFILE=tmp.in
TMPOUTFILE=tmp.out
VARFILE=variables
INFILE=mailserver-step-by-step.md
OUTFILE=mailserver-step-by-step.html
HEADERFILE=header.html
FOOTERFILE=footer.html


cd $(dirname "$0")

cat "$INFILE" >"$TMPINFILE"

cat "$VARFILE" | (

	while read var val ; do

		[ -z "$var" ] && continue

		sed <"$TMPINFILE" >"$TMPOUTFILE" s/$var/$val/g
		mv "$TMPOUTFILE" "$TMPINFILE"
	done
)

sed <"$TMPINFILE" >"$TMPOUTFILE" "s/DATE/$(LC_ALL=C date -u)/g"
mv "$TMPOUTFILE" "$TMPINFILE"

pandoc -f markdown_github -t html --email-obfuscation=none -o "$TMPOUTFILE" "$TMPINFILE"

cat "$HEADERFILE" "$TMPOUTFILE" "$FOOTERFILE" >"$OUTFILE"

rm -f "$TMPINFILE" "$TMPOUTFILE"

