# POMI Web font subsets

These files are generated from the complete Noto Sans SC fonts in the parent
directory by `tool/subset_web_fonts.py`. They retain the four design weights
used by POMI while limiting the Flutter Web download to characters present in
the application UI, smoke data, and web shell.

Regenerate and verify them with:

```text
python -X utf8 tool/subset_web_fonts.py
python -X utf8 tool/subset_web_fonts.py --check
```

Noto Sans SC is distributed under the SIL Open Font License. The generated
subsets remain subject to that license.
