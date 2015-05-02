<p style="font-size:16px;"><b>Loading</b> See when Mac apps are using your network</p>
<img src="README/en.jpg" style="width:100%; max-width:1150px"/>

Similar to the network activity indicator on iOS, Loading shows a spinning progress wheel in your menu bar when your network is being used. Clicking the icon shows the apps that are using your network, and holding down the option key shows the individual processes.

The original project required OS X 10.7 or newer, but that was only because it used 10.7's NSPopover for the licensing functionality. Support for older versions of OS X remain untested.

* * *

Most of the functionality in this app was reverse-engineered from the private NetworkStatistics framework found here:

    /System/Library/PrivateFrameworks/NetworkStatistics.framework

And it uses the private `[NSStatusBarButtonCell _button]` selector on OS X 10.9 and earlier, as `[NSStatusBarButtonCell button]` was not available until Yosemite.

* * *

Lastly, OS X has a large number of bugs regarding NSMenus:

- `[NSMenuItem setView:]` is currently broken, as it will cause the keyboard controls to stop working after using the menu for the first time.

- Using setView on an NSTextView to have wrapped text causes the selection background to render incorrectly, ignores the first mouse click on the menu item, and has the same broken keyboard controls as above.

- NSMenuItems with attributed titles cannot be updated when the item is selected or deselected, so you can't for example have a gray menu item that turns white when selected.

- NSStatusItem's menu will be drawn in the wrong position if you follow the recommended behavior of using `[NSMenuDelegate menuNeedsUpdate:]` OR `menu:updateItem:atIndex:shouldCancel:`. The only workaround I was able to find was swizzling `[NSStatusBarButtonCell trackMouse:inRect:ofView:untilMouseUp:]` and updating the menu there.
