// SPDX-License-Identifier: GPL-3.0-or-later
// Verification tool (not shipped): asks the window server which window a
// mouse-down would land on at each point, to prove click-through beside the
// island. Uses the private SLSFindWindowAndOwner via dlsym, like yabai does.
// Run: swift scripts/hit-test.swift x,y [x,y ...]   (AppKit coordinates, primary display)
import AppKit

typealias MainConnection = @convention(c) () -> Int32
typealias FindWindow = @convention(c) (Int32, Int32, Int32, Int32, UnsafeMutablePointer<CGPoint>,
                                       UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<UInt32>,
                                       UnsafeMutablePointer<Int32>) -> Int32
let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
guard let connectionSymbol = dlsym(skyLight, "SLSMainConnectionID"),
      let findSymbol = dlsym(skyLight, "SLSFindWindowAndOwner") else {
    print("SkyLight symbols not found"); exit(1)
}
let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)()
let find = unsafeBitCast(findSymbol, to: FindWindow.self)

let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
func describe(_ number: UInt32) -> String {
    guard let window = info.first(where: { ($0[kCGWindowNumber as String] as? UInt32) == number }) else { return "window \(number)" }
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    return "\(owner) \(name) (window \(number), layer \(layer))"
}
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
for argument in CommandLine.arguments.dropFirst() {
    let parts = argument.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 2 else { continue }
    var point = CGPoint(x: parts[0], y: primaryHeight - parts[1])
    var local = CGPoint.zero
    var window: UInt32 = 0
    var owner: Int32 = 0
    _ = find(connection, 0, 1, 0, &point, &local, &window, &owner)
    print("(\(parts[0]), \(parts[1])) → \(describe(window))")
}
