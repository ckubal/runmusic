import SwiftUI

struct RunningPersonLoader: View {
    @State private var isAnimating = false
    let size: CGFloat
    
    init(size: CGFloat = 24) {
        self.size = size
    }
    
    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let animationPhase = isAnimating ? 1.0 : 0.0
            
            // Running person in side view
            drawRunningPerson(context: context, center: center, animationPhase: animationPhase)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private func drawRunningPerson(context: GraphicsContext, center: CGPoint, animationPhase: Double) {
        let scale = size / 24.0 // Base size of 24pt
        
        // Animation values
        let legSwing = sin(animationPhase * .pi * 2) * 15 * scale // Leg movement
        let armSwing = sin(animationPhase * .pi * 2) * 12 * scale // Arm movement
        let bodyBounce = abs(sin(animationPhase * .pi * 2)) * 2 * scale // Vertical bounce
        
        // Colors
        let runnerColor = Color.white
        
        // Body position with bounce
        let bodyCenter = CGPoint(x: center.x, y: center.y - bodyBounce)
        
        // Head
        let headRadius = 3 * scale
        let headCenter = CGPoint(x: bodyCenter.x, y: bodyCenter.y - 8 * scale)
        context.fill(
            Path(ellipseIn: CGRect(
                x: headCenter.x - headRadius,
                y: headCenter.y - headRadius,
                width: headRadius * 2,
                height: headRadius * 2
            )),
            with: .color(runnerColor)
        )
        
        // Body (torso)
        let torsoPath = Path { path in
            path.addEllipse(in: CGRect(
                x: bodyCenter.x - 2 * scale,
                y: bodyCenter.y - 4 * scale,
                width: 4 * scale,
                height: 8 * scale
            ))
        }
        context.fill(torsoPath, with: .color(runnerColor))
        
        // Arms (pumping motion)
        drawArm(context: context, 
                shoulder: CGPoint(x: bodyCenter.x - 2 * scale, y: bodyCenter.y - 2 * scale),
                angle: -45 + armSwing, 
                isLeft: true, 
                scale: scale, 
                color: runnerColor)
        
        drawArm(context: context, 
                shoulder: CGPoint(x: bodyCenter.x + 2 * scale, y: bodyCenter.y - 2 * scale),
                angle: -45 - armSwing, 
                isLeft: false, 
                scale: scale, 
                color: runnerColor)
        
        // Legs (running stride)
        drawLeg(context: context, 
                hip: CGPoint(x: bodyCenter.x - 1 * scale, y: bodyCenter.y + 3 * scale),
                angle: legSwing, 
                isLeft: true, 
                scale: scale, 
                color: runnerColor)
        
        drawLeg(context: context, 
                hip: CGPoint(x: bodyCenter.x + 1 * scale, y: bodyCenter.y + 3 * scale),
                angle: -legSwing, 
                isLeft: false, 
                scale: scale, 
                color: runnerColor)
    }
    
    private func drawArm(context: GraphicsContext, shoulder: CGPoint, angle: Double, isLeft: Bool, scale: CGFloat, color: Color) {
        let armLength = 6 * scale
        let forearmLength = 5 * scale
        
        // Upper arm
        let elbowAngle = angle
        let elbow = CGPoint(
            x: shoulder.x + cos(elbowAngle * .pi / 180) * armLength,
            y: shoulder.y + sin(elbowAngle * .pi / 180) * armLength
        )
        
        // Forearm (bent at elbow)
        let forearmAngle = elbowAngle + (isLeft ? -60 : -60)
        let hand = CGPoint(
            x: elbow.x + cos(forearmAngle * .pi / 180) * forearmLength,
            y: elbow.y + sin(forearmAngle * .pi / 180) * forearmLength
        )
        
        // Draw upper arm
        var armPath = Path()
        armPath.move(to: shoulder)
        armPath.addLine(to: elbow)
        context.stroke(armPath, with: .color(color), lineWidth: 2 * scale)
        
        // Draw forearm
        var forearmPath = Path()
        forearmPath.move(to: elbow)
        forearmPath.addLine(to: hand)
        context.stroke(forearmPath, with: .color(color), lineWidth: 2 * scale)
    }
    
    private func drawLeg(context: GraphicsContext, hip: CGPoint, angle: Double, isLeft: Bool, scale: CGFloat, color: Color) {
        let thighLength = 7 * scale
        let shinLength = 6 * scale
        
        // Thigh
        let thighAngle = 90 + angle // Legs point downward with swing
        let knee = CGPoint(
            x: hip.x + cos(thighAngle * .pi / 180) * thighLength,
            y: hip.y + sin(thighAngle * .pi / 180) * thighLength
        )
        
        // Shin (bent at knee for running stride)
        let shinAngle = thighAngle + (isLeft ? 30 : 30) + angle * 0.5
        let foot = CGPoint(
            x: knee.x + cos(shinAngle * .pi / 180) * shinLength,
            y: knee.y + sin(shinAngle * .pi / 180) * shinLength
        )
        
        // Draw thigh
        var thighPath = Path()
        thighPath.move(to: hip)
        thighPath.addLine(to: knee)
        context.stroke(thighPath, with: .color(color), lineWidth: 2.5 * scale)
        
        // Draw shin
        var shinPath = Path()
        shinPath.move(to: knee)
        shinPath.addLine(to: foot)
        context.stroke(shinPath, with: .color(color), lineWidth: 2.5 * scale)
        
        // Draw foot
        let footSize = 2 * scale
        context.fill(
            Path(ellipseIn: CGRect(
                x: foot.x - footSize/2,
                y: foot.y - footSize/2,
                width: footSize,
                height: footSize
            )),
            with: .color(color)
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        RunningPersonLoader(size: 24)
        RunningPersonLoader(size: 32)
        RunningPersonLoader(size: 48)
    }
    .padding()
    .background(Color.black)
}