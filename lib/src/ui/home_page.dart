import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../convert/conversion_controller.dart';
import 'job_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ConversionController _controller = ConversionController();
  bool _dragging = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Choose Excel workbooks',
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xlsm'],
    );
    _add(files.map((file) => file.path).whereType<String>());
  }

  Future<void> _pickFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder of workbooks',
    );
    if (folder != null) _add([folder]);
  }

  Future<void> _pickOutputFolder() async {
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose where the CSV files go',
      initialDirectory: _controller.outputDirectory,
    );
    if (folder != null) _controller.setOutputDirectory(folder);
  }

  void _add(Iterable<String> paths) {
    final added = _controller.addPaths(paths);
    if (added == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new .xlsx or .xlsm files were found.')),
      );
    }
  }

  Future<void> _openOutputFolder() async {
    final folder = _controller.outputDirectory;
    if (folder == null) return;
    await launchUrl(Uri.file(folder));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                onAddFiles: _controller.isRunning ? null : _pickFiles,
                onAddFolder: _controller.isRunning ? null : _pickFolder,
                onClear: _controller.isRunning || _controller.jobs.isEmpty
                    ? null
                    : _controller.clearJobs,
                jobCount: _controller.jobs.length,
              ),
              Expanded(
                child: DropTarget(
                  onDragEntered: (_) => setState(() => _dragging = true),
                  onDragExited: (_) => setState(() => _dragging = false),
                  onDragDone: (detail) {
                    setState(() => _dragging = false);
                    if (_controller.isRunning) return;
                    _add(detail.files.map((file) => file.path));
                  },
                  child: _JobList(
                    controller: _controller,
                    dragging: _dragging,
                    onPickFiles: _pickFiles,
                  ),
                ),
              ),
              _ControlPanel(
                controller: _controller,
                onPickOutput: _pickOutputFolder,
                onOpenOutput: _openOutputFolder,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onAddFiles,
    required this.onAddFolder,
    required this.onClear,
    required this.jobCount,
  });

  final VoidCallback? onAddFiles;
  final VoidCallback? onAddFolder;
  final VoidCallback? onClear;
  final int jobCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Excel to CSV',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'One CSV per sheet, named Workbook(Sheet).csv, with daily '
                  'tabs merged — ready to upload to NotebookLM.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.tonalIcon(
            onPressed: onAddFiles,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add files'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onAddFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Add folder'),
          ),
          if (jobCount > 0) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ],
      ),
    );
  }
}

class _JobList extends StatelessWidget {
  const _JobList({
    required this.controller,
    required this.dragging,
    required this.onPickFiles,
  });

  final ConversionController controller;
  final bool dragging;
  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final jobs = controller.jobs;

    final content = jobs.isEmpty
        ? _EmptyState(onPickFiles: onPickFiles)
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            itemCount: jobs.length,
            itemBuilder: (context, index) {
              final job = jobs[index];
              final isActive =
                  controller.isRunning && controller.currentJob == index;
              return JobTile(
                job: job,
                isActive: isActive,
                activeSheet: isActive ? controller.currentSheet : null,
                previewName: controller.previewName(job),
                onRemove: controller.isRunning
                    ? null
                    : () => controller.removeJob(job),
              );
            },
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (dragging)
          Container(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.85),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 48,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(height: 8),
                Text(
                  'Drop workbooks or folders here',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPickFiles});

  final VoidCallback onPickFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.table_view_outlined,
            size: 56,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('Drag your ledgers here', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '.xlsx and .xlsm workbooks, or a folder containing them',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onPickFiles,
            child: const Text('Choose files'),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.controller,
    required this.onPickOutput,
    required this.onOpenOutput,
  });

  final ConversionController controller;
  final VoidCallback onPickOutput;
  final VoidCallback onOpenOutput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final output = controller.outputDirectory;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.drive_file_move_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Save to', style: theme.textTheme.labelLarge),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  output ?? 'Choose a folder for the CSV files',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: output == null
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: controller.isRunning ? null : onPickOutput,
                child: Text(output == null ? 'Choose…' : 'Change…'),
              ),
              if (output != null)
                IconButton(
                  tooltip: 'Open folder',
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: onOpenOutput,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            // Only applies between rows, so the panel keeps its height while
            // the chips fit on one line and opens up once they wrap.
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _OptionChip(
                label: 'Merge daily sheets',
                tooltip: 'Sheets named after dates (30-Jun-2026, 1-June-2026) '
                    'become one file with a “Sheet date” column, instead of '
                    'one NotebookLM source per day.',
                value: controller.mergeDailySheets,
                onChanged: controller.isRunning
                    ? null
                    : controller.setMergeDailySheets,
              ),
              _OptionChip(
                label: 'Split large sheets',
                tooltip: 'NotebookLM caps a spreadsheet source at about '
                    '100,000 tokens. Oversized sheets are split into as few '
                    'files as possible, each repeating the header row.',
                value: controller.splitLargeSheets,
                onChanged: controller.isRunning
                    ? null
                    : controller.setSplitLargeSheets,
              ),
              _OptionChip(
                label: 'Shorten file names',
                tooltip: 'Drops the tracking id an export tool appends, '
                    'e.g. Stock-Balance__ef86c541-… → Stock-Balance',
                value: controller.tidyFileNames,
                onChanged:
                    controller.isRunning ? null : controller.setTidyFileNames,
              ),
              _OptionChip(
                label: 'Include hidden sheets',
                value: controller.includeHiddenSheets,
                onChanged: controller.isRunning
                    ? null
                    : controller.setIncludeHiddenSheets,
              ),
              _OptionChip(
                label: 'Keep blank rows',
                value: controller.keepBlankRows,
                onChanged:
                    controller.isRunning ? null : controller.setKeepBlankRows,
              ),
              _OptionChip(
                label: 'UTF-8 BOM (for opening in Excel)',
                value: controller.addBom,
                onChanged: controller.isRunning ? null : controller.setAddBom,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.isRunning) ...[
            LinearProgressIndicator(value: controller.progress),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  controller.message ?? _statusLine(controller),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (controller.isRunning)
                OutlinedButton(
                  onPressed: controller.cancel,
                  child: const Text('Cancel'),
                )
              else
                FilledButton.icon(
                  onPressed: controller.canStart ? controller.start : null,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(
                    controller.hasResults ? 'Convert again' : 'Convert',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _statusLine(ConversionController controller) {
    if (controller.jobs.isEmpty) return 'No workbooks added yet.';
    final count = controller.jobs.length;
    return '$count ${count == 1 ? 'workbook' : 'workbooks'} ready.';
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.value,
    required this.onChanged,
    this.tooltip,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      tooltip: tooltip,
      selected: value,
      onSelected: onChanged,
      showCheckmark: true,
      visualDensity: VisualDensity.compact,
    );
  }
}
