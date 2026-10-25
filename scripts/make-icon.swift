import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
func icon(_ size:Int) -> NSImage {
    let image = NSImage(size:NSSize(width:size,height:size))
    image.lockFocus()
    let scale = CGFloat(size)/1024
    let transform = NSAffineTransform(); transform.scale(by:scale); transform.concat()
    let outer = NSBezierPath(roundedRect:NSRect(x:40,y:40,width:944,height:944),xRadius:212,yRadius:212)
    NSGradient(colors:[NSColor(srgbRed:0.24,green:0.38,blue:0.77,alpha:1),NSColor(srgbRed:0.09,green:0.12,blue:0.3,alpha:1)])!.draw(in:outer,angle:-75)
    NSColor.white.withAlphaComponent(0.45).setStroke(); outer.lineWidth = 5; outer.stroke()
    let panel = NSBezierPath(roundedRect:NSRect(x:186,y:200,width:652,height:634),xRadius:118,yRadius:118)
    NSGradient(colors:[NSColor.white.withAlphaComponent(0.32),NSColor.white.withAlphaComponent(0.05)])!.draw(in:panel,angle:-90)
    NSColor.white.withAlphaComponent(0.45).setStroke(); panel.lineWidth = 3; panel.stroke()
    for (x,h,color) in [(286.0,250.0,NSColor.systemMint),(462.0,415.0,NSColor.systemBlue),(638.0,320.0,NSColor.systemPink)] {
        let track = NSBezierPath(roundedRect:NSRect(x:x,y:286,width:100,height:442),xRadius:29,yRadius:29)
        NSColor.black.withAlphaComponent(0.16).setFill(); track.fill()
        let fill = NSBezierPath(roundedRect:NSRect(x:x,y:286,width:100,height:h),xRadius:29,yRadius:29)
        NSGradient(colors:[color.blended(withFraction:0.2,of:.white)!,color])!.draw(in:fill,angle:-90)
        NSColor.white.withAlphaComponent(0.65).setStroke(); track.lineWidth = 3; track.stroke()
    }
    image.unlockFocus(); return image
}
for n in [16,32,128,256,512] {
    for retina in [false,true] {
        let size = n*(retina ? 2:1), image = icon(size)
        let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output+"/icon_\(n)x\(n)\(retina ? "@2x":"").png"))
    }
}
