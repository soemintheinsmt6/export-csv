import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../convert/conversion_controller.dart';
import '../convert/conversion_models.dart';

/// One workbook in the queue, expandable to show what happened to each sheet.
class JobTile extends StatelessWidget {
  const JobTile({
    super.key,
    required this.job,
    required this.isActive,
    required this.activeSheet,
    required this.previewName,
    required this.onRemove,
  });

  final ConversionJob job;
  final bool isActive;
  final String? activeSheet;

  /// What the CSVs will be called, shown before the run so the naming options
  /// are visible rather than a surprise.
  final String previewName;

  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDetail = job.sheets.isNotEmpty || job.error != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        enabled: hasDetail,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _StatusIcon(job: job, isActive: isActive),
        title: Text(
          job.fileName,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _subtitle(),
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: job.status == JobStatus.failed
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: onRemove == null
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Remove from list',
                onPressed: onRemove,
              ),
        children: [
          if (job.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
              child: Text(
                job.error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          for (final sheet in job.sheets) _SheetRow(sheet: sheet),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _subtitle() {
    if (job.error != null) return job.error!;
    return switch (job.status) {
      JobStatus.pending => '→ $previewName',
      JobStatus.converting => activeSheet == null
          ? 'Reading workbook…'
          : 'Converting “$activeSheet”…',
      JobStatus.cancelled => 'Cancelled',
      JobStatus.done || JobStatus.failed =>
        '${job.convertedCount} of ${job.sheetCount} sheets · '
            '${_formatCount(job.rowCount)} rows',
    };
  }

  static String _formatCount(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.job, required this.isActive});

  final ConversionJob job;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isActive && job.status == JobStatus.converting) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    return switch (job.status) {
      JobStatus.done => Icon(Icons.check_circle, color: scheme.primary),
      JobStatus.failed => Icon(Icons.error_outline, color: scheme.error),
      JobStatus.cancelled =>
        Icon(Icons.remove_circle_outline, color: scheme.outline),
      _ => Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
    };
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.sheet});

  final SheetOutcome sheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final converted = sheet.status == SheetStatus.converted;
    final label = switch (sheet) {
      SheetOutcome(status: SheetStatus.converted, wasSplit: true) =>
        '${p.basename(sheet.outputPaths.first)}  +${sheet.outputPaths.length - 1} more',
      SheetOutcome(status: SheetStatus.converted, wasMerged: true) =>
        '${p.basename(sheet.outputPath!)}  (${sheet.mergedSheetCount} sheets)',
      SheetOutcome(status: SheetStatus.converted) =>
        p.basename(sheet.outputPath!),
      _ => '${sheet.sheetName} — ${sheet.message ?? 'Skipped'}',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 2, 16, 2),
      child: Row(
        children: [
          Icon(
            converted ? Icons.arrow_right_alt : Icons.horizontal_rule,
            size: 16,
            color: converted
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: converted
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (converted)
            Text(
              '${sheet.rowCount} rows',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
