import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:otoha/l10n/app_localizations.dart';
import 'package:window_manager/window_manager.dart';

import '../app/theme.dart';

/// Lists every license registered with [LicenseRegistry] and shows one in full.
///
/// Flutter's own `LicensePage` swaps its detail pane with a fixed 500 ms
/// animation that reduced motion cannot turn off, so the desktop app renders
/// the same registry itself. Selecting a package is an instant swap.
class OtohaLicensePage extends StatefulWidget {
  const OtohaLicensePage({required this.applicationName, super.key});

  final String applicationName;

  @override
  State<OtohaLicensePage> createState() => _OtohaLicensePageState();
}

class _OtohaLicensePageState extends State<OtohaLicensePage> {
  late final Future<List<_PackageLicense>> _licenses = _loadLicenses();
  _PackageLicense? _selected;

  Future<List<_PackageLicense>> _loadLicenses() async {
    final byPackage = <String, _PackageLicense>{};
    await for (final entry in LicenseRegistry.licenses) {
      final name = entry.packages.isEmpty
          ? 'Unknown'
          : entry.packages.join(', ');
      final text = entry.paragraphs
          .map((paragraph) => paragraph.text)
          .join('\n');
      final existing = byPackage[name];
      byPackage[name] = existing == null
          ? _PackageLicense(name: name, text: text)
          : _PackageLicense(name: name, text: '${existing.text}\n\n$text');
    }
    final list = byPackage.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final selected = _selected;
    final page = Scaffold(
      backgroundColor: OtohaColors.canvas,
      appBar: AppBar(
        backgroundColor: OtohaColors.canvas,
        // The list uses the standard BackButton, which pops the route. A license
        // detail returns to the list instead, so it needs its own control.
        leading: selected == null
            ? const BackButton()
            : IconButton(
                key: const Key('own-license-back'),
                tooltip: l10n.back,
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(selected?.name ?? widget.applicationName),
      ),
      body: selected != null
          ? _LicenseText(license: selected)
          : FutureBuilder<List<_PackageLicense>>(
              future: _licenses,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final licenses = snapshot.data!;
                return ListView.separated(
                  padding: const EdgeInsets.all(AppMetrics.workspacePadding),
                  itemCount: licenses.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final license = licenses[index];
                    return ListTile(
                      key: Key('own-license-package-${license.name}'),
                      title: Text(license.name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => setState(() => _selected = license),
                    );
                  },
                );
              },
            ),
    );
    const desktopPlatforms = <TargetPlatform>{
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    };
    if (kIsWeb || !desktopPlatforms.contains(defaultTargetPlatform)) {
      return page;
    }
    // The window has no native title bar, so the strip right of the back
    // button is the drag handle, as it was on the Flutter LicensePage.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        page,
        Positioned(
          top: 0,
          left: kToolbarHeight,
          right: 0,
          height: kToolbarHeight,
          child: GestureDetector(
            key: const Key('license-page-drag-area'),
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
          ),
        ),
      ],
    );
  }
}

class _PackageLicense {
  const _PackageLicense({required this.name, required this.text});

  final String name;
  final String text;
}

class _LicenseText extends StatelessWidget {
  const _LicenseText({required this.license});

  final _PackageLicense license;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppMetrics.workspacePadding),
      child: SelectableText(
        license.text,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
