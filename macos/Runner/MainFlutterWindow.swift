import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 900, height: 680)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "Excel to CSV"
    self.contentMinSize = NSSize(width: 720, height: 520)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
