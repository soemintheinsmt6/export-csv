# Excel to CSV

A Flutter desktop app (macOS and Windows) that splits Excel workbooks into one
CSV per sheet, so ledgers can be uploaded to NotebookLM — which does not accept
`.xlsx`, and chokes on a whole workbook printed to PDF.

Each sheet becomes `Workbook(Sheet).csv`, for example:

```
AR Ledger 2024.xlsx
  ├─ January   →  AR Ledger 2024(January).csv
  ├─ February  →  AR Ledger 2024(February).csv
  └─ Summary   →  AR Ledger 2024(Summary).csv
```

The file name carries both the workbook and the sheet, which is all NotebookLM
shows in its source list.

## Using it

1. Drag workbooks (or a folder of them) onto the window, or use **Add files** /
   **Add folder**. `.xlsx` and `.xlsm` are supported.
2. Pick the folder the CSVs go into. It defaults to a `csv_for_notebooklm`
   folder next to the first workbook.
3. Press **Convert**, then upload the CSVs to NotebookLM.

Options along the bottom:

| Option | Default | Effect |
| --- | --- | --- |
| Merge daily sheets | on | Combines date-named tabs into one file with a `Sheet date` column, instead of one source per day |
| Split large sheets | on | Splits a sheet too big for one NotebookLM source into as few files as possible, each repeating the header |
| Shorten file names | on | Drops a tracking id an export tool appended, so `Stock-Balance__ef86c541-70a3-…` becomes `Stock-Balance` |
| Include hidden sheets | on | Hidden tabs are exported too, since they sometimes hold real data |
| Keep blank rows | off | Off drops blank rows; on restores the gaps the sheet had |
| UTF-8 BOM | off | Turn on if you also want to open the CSVs in Excel and keep non-Latin text readable |

Re-running overwrites files of the same name in the output folder.

## What it does with the awkward parts of a workbook

- **Formulas** export as the value Excel last calculated (`1,234.56`), not as
  `=SUM(B2:B40)`. If a workbook was saved without cached results, the formula is
  written instead so nothing disappears silently.
- **Dates** follow the cell's number format: `2024-03-15`, `2024-03-15 09:30:00`
  or `09:30:00`, rather than the serial number Excel stores. Workbooks using the
  1904 date system are handled.
- **Money and percentages** stay as plain numbers — no thousands separators or
  currency symbols to confuse a reader.
- **Float noise** is trimmed, so a stored `1234.5600000000002` writes as
  `1234.56`.
- **Empty sheets** produce no file. Blank leading and trailing rows are dropped.
- **Sheet names** that contain `/`, `:` or other characters a file system
  rejects are rewritten with `_`, and collisions get a ` (2)` suffix.
- **Oversized sheets** are split into `Sheet part 1 of 3.csv` and so on. See
  below for why, and what a "part" contains.
- **Legacy `.xls`** files are reported with an explanation, not a crash: open
  them in Excel and re-save as `.xlsx`.

Workbooks are read a row at a time in a background isolate, so the window stays
responsive and a large ledger does not have to fit in memory.

## Merging daily sheets

A month of tabs named `1-June-2026`, `2-Jun-2026`, `30-6-2026` is one table
split across thirty sheets, not thirty documents — but it costs thirty of a
notebook's sources. **Merge daily sheets**, on by default, writes them as one
file instead, adding a leading `Sheet date` column holding the day each row
came from:

```
Sheet date,No.,Code,Item,Qty
2026-06-01,1,A1,Widget,5
2026-06-02,2,A2,Gadget,7
```

- Tab names are read as day-first (`17-6-2026`, `1-Jun-26`, `13 June 2026`) and
  as ISO (`2026-06-17`).
- A label after the date starts its own series, so `17-6-2026 Plan Ground` is
  merged with the other `Plan Ground` days rather than with the plain ones —
  they are different tables that share a naming habit.
- The header block is written once. Later days drop their copy of it only when
  it matches exactly; a day with a different shape keeps every row it had.
- A single dated sheet is left alone, since one day is not a series.
- Names that only look like dates are left alone too. `2324-6-26` is a tab
  covering the 23rd and 24th, not the year 2324, so it stays its own file
  rather than being guessed at.

The merged file is still split if it exceeds a source's limit, so a month of
dailies typically ends up as one to three sources instead of thirty. Turn the
option off to get one file per sheet, whatever the tabs are called.

## Why sheets get split

NotebookLM measures a **spreadsheet** source in tokens, and caps it far lower
than the 500,000-word limit that applies to documents — around **100,000
tokens**. A CSV nowhere near the word limit is still refused once it crosses it.
Myanmar script makes this arrive sooner: it costs roughly a token per character
where Latin text costs about a quarter of that, so a Burmese ledger hits the
ceiling at a fraction of the file size an English one would.

When a sheet is too big, it is written as several files:

- each part is **filled to just under the limit** before the next is started,
  because sources — not files — are what a notebook runs out of
- **rows are never split** across parts
- every part **repeats the sheet's header**, including a title or summary line
  above it, so a part can be read on its own
- concatenating the parts (minus the repeated headers) reproduces the original
  sheet exactly

## Text encoding

Every CSV is written as **UTF-8**, always. This matters more than it sounds for
non-Latin ledgers: Excel's own *Save As* offers `CSV (Comma delimited)`, which
writes the legacy ANSI code page of the system locale — and no ANSI code page
covers Myanmar script, so every Burmese character is replaced with `?`,
permanently, in the saved file. Excel's `CSV UTF-8` is the safe one, and it is
what this app always produces.

The **UTF-8 BOM** option does not change the encoding; it only adds the marker
that tells Excel the file is UTF-8. Leave it off for NotebookLM. Turn it on if
you also want to double-click the CSVs open in Excel, otherwise Excel assumes
ANSI and shows Burmese as mojibake. (With it off you can still open them cleanly
via *Data → From Text/CSV → 65001: Unicode (UTF-8)*.)

Note that Unicode Burmese and Zawgyi occupy the same code points with different
meanings. Whatever the workbook contains is passed through unchanged — but only
Unicode Burmese is readable by a language model, so convert Zawgyi first if that
is what your ledgers use.

## Notes for NotebookLM

**Sources per notebook** is the limit you will hit first:

| Plan | Sources per notebook | Notebooks |
| --- | --- | --- |
| Free | 50 | 100 |
| Pro (Google AI Pro) | 300 | 500 |
| Ultra (Google AI Ultra) | 600 | 500 |

A workbook of daily tabs turns into dozens of sources, so budget before
converting: ten such workbooks can exceed even the Pro allowance. Removing
workbooks from the queue, or exporting only the sheets you need, is cheaper than
a bigger plan.

**Notebooks cannot be queried together.** Each notebook's chat sees only its own
sources; collections group notebooks without combining them, and there is no
merge. To ask a question spanning several notebooks, attach them to a chat in
the Gemini app instead (`+` → NotebookLM). For a recurring cross-cutting view, a
dedicated notebook holding just the summary sheets works better than relying on
that.

## Development

```bash
flutter test          # unit tests plus an end-to-end run through the isolate
flutter run -d macos  # or: flutter run -d windows
```

Layout:

```
lib/src/xlsx/
  xlsx_workbook.dart   streams rows out of the OOXML inside an .xlsx
  cell_format.dart     decides whether a number format means a date
  cell_value.dart      serial dates, number normalisation
lib/src/convert/
  converter.dart       the conversion run, workbook by workbook
  sheet_writer.dart    splitting, header repetition, part naming
  source_budget.dart   the token estimate the split budget is spent against
  csv_writer.dart      RFC 4180 quoting, streamed to disk
  output_naming.dart   Workbook(Sheet).csv, sanitising and collisions
  conversion_runner.dart   the background isolate
  conversion_controller.dart  queue, options and progress for the UI
lib/src/ui/            the window
test/fixtures/         builds synthetic .xlsx files, including cell shapes a
                       spreadsheet library would not emit (cached formula
                       results, 1904 dates, custom number formats)
```

The `.xlsx` reading is deliberately hand-written rather than taken from a
spreadsheet package. The packages available discard the cached result Excel
stores with each formula cell, which would export a ledger's totals as
`=SUM(B2:B40)` instead of the number. Parsing the OOXML directly also means rows
can be streamed instead of built into an object graph.

## Releasing

Two GitHub Actions workflows build the installers. Both run on a push to the
**`deploy`** branch, and can also be started by hand from the Actions tab
(*Run workflow*).

| Workflow | Runner | Produces |
| --- | --- | --- |
| `.github/workflows/build-macos.yml` | `macos-latest` | `ExcelToCSV-<version>-macos.dmg` |
| `.github/workflows/build-windows.yml` | `windows-latest` | `ExcelToCSV-<version>-windows-x64-setup.exe` |

Each one installs dependencies, runs `flutter analyze` and `flutter test`, then
builds and packages. A deploy that fails its tests produces no installer.

To cut a release:

```bash
# set the version first — it names the installers
$EDITOR pubspec.yaml          # version: 1.0.1+2

git switch -c deploy          # first time only
git merge main
git push -u origin deploy
```

The installers appear as workflow artifacts on the run. The version comes from
`pubspec.yaml`, so bump it before pushing or the new build overwrites the old
name.

### The installers are not code-signed

Neither is signed with a paid developer certificate, so both operating systems
warn on first launch. This is expected, not a fault in the build.

- **macOS** — the app is signed ad-hoc, which is enough to run but not enough
  for Gatekeeper. On first launch, right-click the app and choose *Open*, then
  confirm. If macOS insists the app is damaged, clear the quarantine flag:
  `xattr -dr com.apple.quarantine "/Applications/Excel to CSV.app"`.
- **Windows** — SmartScreen shows *"Windows protected your PC"*. Choose *More
  info* → *Run anyway*. The installer writes to the user's own program folder
  by default, so it does not ask for administrator rights.

Signing properly needs an Apple Developer account (and notarisation) and a
Windows code-signing certificate. Both are paid, and neither is needed to run
the app yourself.

### Windows notes

The installer bundles the MSVC runtime DLLs beside the executable, so it does
not depend on the Visual C++ Redistributable being present. `windows/packaging/
export_csv.iss` is the Inno Setup script; its `AppId` identifies the app to
Windows across upgrades and must never change.

## File permissions

**Windows** — nothing to grant. The app runs with your own account's rights
(the manifest requests no elevation), so it reads and writes anywhere you can.

**macOS** — the app is sandboxed, and holds exactly two entitlements:

| Entitlement | What it allows |
| --- | --- |
| `files.user-selected.read-write` | Read and write any file or folder you pick in a dialog or drop onto the window |
| `files.downloads.read-write` | Read and write `~/Downloads` without picking it first |

Anything else stays off limits, which is why the output folder must be one you
chose. Picking individual workbooks grants access to *those files* and nothing
around them — not their parent folder — so the app defaults its output folder
to one you picked or dropped whole, and checks it is really writable before
starting, rather than failing halfway through a run.

If you see *"Cannot write to …"*, press **Change…** and pick the destination
folder; that act of picking is what grants the access.
