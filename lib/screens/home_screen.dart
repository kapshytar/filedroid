import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:provider/provider.dart';
import '../providers/device_provider.dart';
import '../providers/file_browser_provider.dart';
import '../providers/transfer_provider.dart';
import '../services/mount_service.dart';
import '../utils/theme.dart';
import '../widgets/adb_setup_screen.dart';
import '../widgets/browser_toolbar.dart';
import '../widgets/device_panel.dart';
import '../widgets/file_browser.dart';
import '../widgets/transfer_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showTransfers = true;
  bool _hasLoadedBrowser = false;
  DeviceProvider? _deviceProv;
  final _mountService = MountService();
  bool _isMounting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deviceProv = context.read<DeviceProvider>();
      _deviceProv!.initialize();
      _deviceProv!.addListener(_onDeviceChanged);
      context.read<TransferProvider>().onTransferComplete = () {
        context.read<FileBrowserProvider>().refresh();
      };
    });
  }

  void _onDeviceChanged() {
    if (_hasLoadedBrowser) return;
    if (_deviceProv?.hasDevice == true) {
      _hasLoadedBrowser = true;
      context.read<FileBrowserProvider>().navigateTo('/sdcard');
    }
  }

  @override
  void dispose() {
    _deviceProv?.removeListener(_onDeviceChanged);
    super.dispose();
  }

  Future<void> _runMount(Future<MountResult> Function() action) async {
    if (_isMounting) return;
    setState(() => _isMounting = true);
    try {
      final result = await action();
      if (!mounted) return;
      _showMountResult(result);
    } finally {
      if (mounted) setState(() => _isMounting = false);
    }
  }

  void _showMountResult(MountResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FileDroidTheme.bgElevated,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              result.success ? Icons.check_circle_outline : Icons.error_outline,
              color: result.success
                  ? FileDroidTheme.greenSuccess
                  : FileDroidTheme.roseError,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              result.success ? 'Готово' : 'Ошибка',
              style: TextStyle(
                color: result.success
                    ? FileDroidTheme.greenSuccess
                    : FileDroidTheme.roseError,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          result.output,
          style: const TextStyle(
            color: FileDroidTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK',
                style: TextStyle(color: FileDroidTheme.accentCyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deviceProv = context.watch<DeviceProvider>();

    return MacosWindow(
      titleBar: TitleBar(
        height: 48,
        centerTitle: false,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: FileDroidTheme.bgSurface.withValues(alpha: 0.9),
        ),
        title: Row(
          children: [
            // FileDroid logo in title bar, aligned left with sidebar
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: FileDroidTheme.uploadGradient,
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Center(
                child: Icon(Icons.android, color: Colors.white, size: 17),
              ),
            ),
            const SizedBox(width: 8),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FileDroid',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: FileDroidTheme.textPrimary,
                  ),
                ),
                Text(
                  'Android Transfer',
                  style: TextStyle(
                    fontSize: 10,
                    color: FileDroidTheme.textTertiary,
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Transfer panel toggle button
            Tooltip(
              message: _showTransfers ? 'Hide Transfers' : 'Show Transfers',
              waitDuration: const Duration(milliseconds: 500),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      setState(() => _showTransfers = !_showTransfers),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _showTransfers
                          ? FileDroidTheme.accentIndigo
                              .withValues(alpha: 0.15)
                          : FileDroidTheme.bgElevated,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: FileDroidTheme.borderLight),
                    ),
                    child: Center(
                      child: Text(
                        'T',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _showTransfers
                              ? FileDroidTheme.accentCyan
                              : FileDroidTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Mount buttons separator
            Container(
              width: 1,
              height: 20,
              color: FileDroidTheme.borderLight,
            ),
            const SizedBox(width: 8),
            // Mount Phone button
            _TitleBarButton(
              label: 'Mount',
              tooltip: 'Монтировать телефон (~/Phone)',
              icon: Icons.usb,
              color: FileDroidTheme.accentCyan,
              loading: _isMounting,
              onTap: () => _runMount(_mountService.mountPhone),
            ),
            const SizedBox(width: 4),
            // Mount System button
            _TitleBarButton(
              label: 'Sys',
              tooltip: 'Монтировать системный раздел (~/Phone-System)',
              icon: Icons.storage,
              color: FileDroidTheme.accentTeal,
              loading: _isMounting,
              onTap: () => _runMount(_mountService.mountSystem),
            ),
            const SizedBox(width: 4),
            // Unmount button
            _TitleBarButton(
              label: 'Unmount',
              tooltip: 'Размонтировать телефон',
              icon: Icons.eject,
              color: FileDroidTheme.roseError,
              loading: _isMounting,
              onTap: () => _runMount(_mountService.unmountPhone),
            ),
          ],
        ),
      ),
      child: _buildBody(deviceProv),
    );
  }

  Widget _buildBody(DeviceProvider deviceProv) {
    if (deviceProv.isLoading) {
      return Container(
        color: FileDroidTheme.bgPrimary,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FileDroidTheme.accentIndigo,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Initializing...',
                style: TextStyle(
                  fontSize: 14,
                  color: FileDroidTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!deviceProv.adbAvailable) {
      return AdbSetupScreen(onRetry: () => deviceProv.retryInitialize());
    }

    return Stack(
      children: [
        // Background
        Container(color: FileDroidTheme.bgPrimary),
        // Ambient glow orbs
        ..._buildGlowOrbs(),
        // Main layout
        Row(
          children: [
            // Sidebar
            const DevicePanel(),
            // Divider
            Container(width: 1, color: FileDroidTheme.borderSubtle),
            // Content area
            Expanded(
              child: Column(
                children: [
                  const BrowserToolbar(),
                  const Expanded(child: FileBrowser()),
                ],
              ),
            ),
            // Transfer panel
            if (_showTransfers) const TransferPanel(),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildGlowOrbs() {
    return [
      Positioned(
        top: -100,
        left: -80,
        child: _GlowOrb(color: FileDroidTheme.accentIndigo, size: 350),
      ),
      Positioned(
        bottom: -120,
        right: -60,
        child: _GlowOrb(color: FileDroidTheme.accentCyan, size: 300),
      ),
      Positioned(
        bottom: -80,
        left: -40,
        child: _GlowOrb(color: FileDroidTheme.roseError, size: 250),
      ),
      Positioned(
        top: -60,
        right: -100,
        child: _GlowOrb(color: FileDroidTheme.purple, size: 280),
      ),
    ];
  }
}

class _TitleBarButton extends StatefulWidget {
  final String label;
  final String tooltip;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;

  const _TitleBarButton({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = !widget.loading;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _hovering && enabled
                  ? widget.color.withValues(alpha: 0.18)
                  : FileDroidTheme.bgElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: enabled
                    ? widget.color.withValues(alpha: 0.45)
                    : FileDroidTheme.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.loading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: widget.color,
                    ),
                  )
                else
                  Icon(widget.icon, size: 13, color: enabled ? widget.color : FileDroidTheme.textTertiary),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enabled ? widget.color : FileDroidTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.18),
        ),
      ),
    );
  }
}
