import SceneKit
import SwiftUI

// 3D body hologram — a stylized parametric figure whose waist and hip are
// driven by the user's REAL measurements (scan or tape). Deliberately a
// glowing model, not a photoreal body: the shape talks, the person stays
// private (guardrail #7), and there's no thin/fat judgement anywhere
// (guardrail #4) — just "this is your silhouette, watch it change".
// SMPL-grade mesh (v1.5) will replace the geometry, not this card.

struct BodyModelCard: View {
    let waistCm: Double
    let hipCm: Double
    let heightCm: Double
    /// Server-driven level — the hedgehog companion grows with it.
    var level: Int = 2
    /// Server-driven streak — unlocks the hedgehog's wardrobe.
    var streak: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wardrobe milestones (mirror the streak celebration milestones).
    private var gear: String {
        var items: [String] = []
        if streak >= 3 { items.append("🧣") }
        if streak >= 7 { items.append("🎽") }
        if streak >= 14 { items.append("😎") }
        if streak >= 30 { items.append("🦸") }
        if streak >= 50 { items.append("🔥") }
        return items.joined()
    }

    private var petLine: String {
        let base = "Nhím Tím cấp \(level)"
        if !gear.isEmpty {
            return "\(base) · chuỗi \(streak) ngày \(gear)"
        }
        let next = streak >= 0 ? 3 - streak : 3
        return "\(base) — chuỗi \(max(next, 1)) ngày nữa là nhím có khăn quàng 🧣"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mô hình của bạn").font(.viet(13)).foregroundStyle(Color(hex: 0xD9CCF2))
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "rotate.3d").font(.system(size: 11))
                    Text("kéo để xoay").font(.viet(11))
                }
                .foregroundStyle(Color(hex: 0x8F82B8))
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 0, trailing: 16))

            SceneView(
                scene: BodyHologram.scene(
                    waistCm: waistCm, hipCm: hipCm, heightCm: heightCm,
                    level: level, streak: streak, animated: !reduceMotion
                ),
                options: [.allowsCameraControl]
            )
            .frame(height: 300)

            Text("Mô phỏng theo số đo — không phải ảnh cơ thể bạn.")
                .font(.viet(11)).foregroundStyle(Color(hex: 0x8F82B8))
                .frame(maxWidth: .infinity)
            Text(petLine)
                .font(.viet(11, .semibold)).foregroundStyle(Color(hex: 0xC2ABEC))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0x1D1830), Color(hex: 0x2A2244)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

enum BodyHologram {
    /// Base half-breadth profiles (fraction of body height from the crown →
    /// radius as fraction of height). A generic upright figure; the waist
    /// and hip rows of the torso get scaled to the user's measured semi-axes.
    private static let torsoProfile: [(t: Double, r: Double)] = [
        // Big rounded head (soft anime/chibi proportions) → slim neck.
        (0.000, 0.018), (0.016, 0.064), (0.050, 0.090), (0.082, 0.092), (0.112, 0.074),
        (0.142, 0.034), (0.166, 0.060), (0.196, 0.108), (0.224, 0.104),
        (0.258, 0.098), (0.312, 0.088), (0.380, 0.078), (0.430, 0.086),
        (0.470, 0.094), (0.520, 0.090), (0.560, 0.074), (0.585, 0.042),
    ]
    private static let legProfile: [(t: Double, r: Double)] = [
        (0.500, 0.050), (0.600, 0.048), (0.720, 0.033), (0.820, 0.035),
        (0.920, 0.020), (0.955, 0.023), (1.000, 0.012),
    ]
    private static let armProfile: [(t: Double, r: Double)] = [
        (0.195, 0.024), (0.250, 0.021), (0.360, 0.016), (0.460, 0.019),
        (0.515, 0.010),
    ]
    private static let waistRow = 0.380
    private static let hipRow = 0.470
    // Cross-sections are ellipses; depth ≈ 0.72 × breadth on average.
    private static let depthAspect = 0.72
    // Ramanujan perimeter of an ellipse with a=1, b=depthAspect.
    private static let perimeterFactor = Double.pi *
        (3 * (1 + depthAspect) - ((3 + depthAspect) * (1 + 3 * depthAspect)).squareRoot())

    static func scene(waistCm: Double, hipCm: Double, heightCm: Double, level: Int, streak: Int, animated: Bool) -> SCNScene {
        let scene = SCNScene()
        // SceneView paints its own backdrop — match the card's dark stage
        // (ceremony palette) so the hologram glows.
        scene.background.contents = UIColor(red: 0x1D / 255.0, green: 0x18 / 255.0, blue: 0x30 / 255.0, alpha: 1)

        let (waistScale, hipScale) = scales(waistCm: waistCm, hipCm: hipCm, heightCm: heightCm)
        let figure = SCNNode()
        // Torso+head carries the measured waist/hip; limbs are stylized.
        figure.addChildNode(part(torsoProfile, aspect: 0.72, x: 0, waistScale: waistScale, hipScale: hipScale))
        let legSpread = Float(0.05 * hipScale.squareRoot())
        figure.addChildNode(part(legProfile, aspect: 0.85, x: -legSpread))
        figure.addChildNode(part(legProfile, aspect: 0.85, x: legSpread))
        figure.addChildNode(part(armProfile, aspect: 1.0, x: -0.126))
        figure.addChildNode(part(armProfile, aspect: 1.0, x: 0.126))
        // A minimal, friendly face so the model reads as a little character
        // (like the Nhím companion) instead of a blank silhouette. Eyes only:
        // neutral, no mouth or gender cues — the body stays a stylised
        // measurement model (guardrail #4/#7 intact).
        figure.addChildNode(faceEyes())

        if animated {
            figure.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 14)))
        } else {
            figure.eulerAngles.y = 0.5
        }
        scene.rootNode.addChildNode(figure)

        // The companion: Nhím Tím, raised by real activity (level = server
        // XP). Bigger level, bigger hedgehog; a crown from level 10.
        // Category 2: lit by its own soft light, NOT the harsh hologram
        // rims (they wash the matte purple out to white).
        let hedgehog = hedgehogNode(level: level, streak: streak, animated: animated)
        hedgehog.position = SCNVector3(0.30, -0.5, 0.18)
        hedgehog.eulerAngles.y = -0.55
        hedgehog.enumerateHierarchy { node, _ in node.categoryBitMask = 2 }
        scene.rootNode.addChildNode(hedgehog)

        let petLight = SCNNode()
        petLight.light = SCNLight()
        petLight.light?.type = .omni
        petLight.light?.intensity = 320
        petLight.light?.categoryBitMask = 2
        petLight.position = SCNVector3(0.55, 0.0, 0.9)
        scene.rootNode.addChildNode(petLight)

        // Holographic pedestal: glowing disc + two bright rings (mint + violet).
        let disc = SCNNode(geometry: SCNCylinder(radius: 0.34, height: 0.004))
        let discMat = SCNMaterial()
        discMat.lightingModel = .constant
        discMat.diffuse.contents = UIColor.black
        discMat.emission.contents = UIColor(red: 0.24, green: 0.86, blue: 0.72, alpha: 1)
        discMat.transparency = 0.22
        discMat.blendMode = .add
        discMat.writesToDepthBuffer = false
        disc.geometry?.firstMaterial = discMat
        disc.position.y = -0.505
        scene.rootNode.addChildNode(disc)

        let innerRing = SCNNode(geometry: SCNTorus(ringRadius: 0.35, pipeRadius: 0.006))
        let innerMat = SCNMaterial()
        innerMat.lightingModel = .constant
        innerMat.emission.contents = UIColor(red: 0.28, green: 0.95, blue: 0.78, alpha: 1)
        innerMat.blendMode = .add
        innerMat.writesToDepthBuffer = false
        innerRing.geometry?.firstMaterial = innerMat
        innerRing.position.y = -0.5
        scene.rootNode.addChildNode(innerRing)

        let outerRing = SCNNode(geometry: SCNTorus(ringRadius: 0.44, pipeRadius: 0.0045))
        let outerMat = SCNMaterial()
        outerMat.lightingModel = .constant
        outerMat.emission.contents = UIColor(red: 0.60, green: 0.48, blue: 0.98, alpha: 1)
        outerMat.blendMode = .add
        outerMat.writesToDepthBuffer = false
        outerRing.geometry?.firstMaterial = outerMat
        outerRing.position.y = -0.5
        scene.rootNode.addChildNode(outerRing)

        if animated {
            // breathing pulse on the rings — the stage feels alive
            innerRing.runAction(.repeatForever(.sequence([
                .scale(to: 1.05, duration: 1.6),
                .scale(to: 1.0, duration: 1.6),
            ])))
            outerRing.runAction(.repeatForever(.sequence([
                .scale(to: 0.97, duration: 2.1),
                .scale(to: 1.0, duration: 2.1),
            ])))
        }

        // Scan beam sweeping the figure — bright mint slab, blooms as it passes.
        if animated {
            let beam = SCNNode(geometry: SCNBox(width: 0.52, height: 0.006, length: 0.52, chamferRadius: 0))
            let beamMat = SCNMaterial()
            beamMat.lightingModel = .constant
            beamMat.emission.contents = UIColor(red: 0.30, green: 0.98, blue: 0.80, alpha: 1)
            beamMat.diffuse.contents = UIColor.black
            beamMat.transparency = 0.5
            beamMat.blendMode = .add
            beamMat.isDoubleSided = true
            beamMat.writesToDepthBuffer = false
            beam.geometry?.firstMaterial = beamMat
            beam.position.y = -0.55
            beam.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 1.1, z: 0, duration: 2.6),
                .moveBy(x: 0, y: -1.1, z: 0, duration: 2.6),
            ])))
            scene.rootNode.addChildNode(beam)
        }

        // Lighting: cool key + green and purple rims — the ceremony palette.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 550
        key.light?.categoryBitMask = 3 // body + pet
        key.eulerAngles = SCNVector3(-0.6, 0.4, 0)
        scene.rootNode.addChildNode(key)

        let rimGreen = SCNNode()
        rimGreen.light = SCNLight()
        rimGreen.light?.type = .omni
        rimGreen.light?.color = UIColor(red: 0.20, green: 0.70, blue: 0.49, alpha: 1)
        // Tuned down: the body is now a LIT (blinn) surface, not a `.constant`
        // one that ignored these — 900 would blow it out.
        rimGreen.light?.intensity = 360
        rimGreen.light?.categoryBitMask = 1 // hologram only
        rimGreen.position = SCNVector3(0.9, 0.1, 0.6)
        scene.rootNode.addChildNode(rimGreen)

        let rimPurple = SCNNode()
        rimPurple.light = SCNLight()
        rimPurple.light?.type = .omni
        rimPurple.light?.color = UIColor(red: 0.54, green: 0.39, blue: 0.82, alpha: 1)
        rimPurple.light?.intensity = 300
        rimPurple.light?.categoryBitMask = 1 // hologram only
        rimPurple.position = SCNVector3(-0.9, 0.4, -0.4)
        scene.rootNode.addChildNode(rimPurple)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        // A touch brighter so the toon body's shadow side stays cute, not murky.
        ambient.light?.intensity = 210
        ambient.light?.categoryBitMask = 3
        scene.rootNode.addChildNode(ambient)

        // Floating sparkle motes around the figure — the "hologram dust".
        if animated {
            scene.rootNode.addChildNode(sparkles())
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.position = SCNVector3(0, 0.07, 1.32)
        // Volumetric glow — emissive surfaces bloom into a soft halo.
        camera.camera?.wantsHDR = true
        camera.camera?.bloomIntensity = 0.45
        camera.camera?.bloomThreshold = 0.86
        camera.camera?.bloomBlurRadius = 6
        camera.camera?.wantsExposureAdaptation = false
        scene.rootNode.addChildNode(camera)

        return scene
    }

    /// A cloud of tiny glowing motes drifting around the hologram.
    private static func sparkles() -> SCNNode {
        let root = SCNNode()
        let tints = [
            UIColor(red: 0.45, green: 0.95, blue: 0.92, alpha: 1),
            UIColor(red: 0.54, green: 0.45, blue: 0.90, alpha: 1),
            UIColor.white,
        ]
        for i in 0..<16 {
            // Deterministic scatter in a cylinder around the figure.
            let a = Double(i) / 16 * 2 * .pi * 2.6
            let radius = 0.28 + Double((i * 37) % 20) / 100.0
            let y = -0.45 + Double((i * 53) % 100) / 100.0
            let size = 0.006 + Double((i * 17) % 5) / 1000.0
            let mote = SCNNode(geometry: SCNSphere(radius: size))
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.emission.contents = tints[i % tints.count]
            mat.blendMode = .add
            mat.writesToDepthBuffer = false
            mote.geometry?.firstMaterial = mat
            mote.position = SCNVector3(Float(cos(a) * radius), Float(y), Float(sin(a) * radius))
            let dur = 2.4 + Double((i * 29) % 30) / 10.0
            mote.runAction(.repeatForever(.sequence([
                .group([
                    .moveBy(x: 0, y: 0.12, z: 0, duration: dur),
                    .fadeOpacity(to: 0.2, duration: dur),
                ]),
                .group([
                    .moveBy(x: 0, y: -0.12, z: 0, duration: dur),
                    .fadeOpacity(to: 1, duration: dur),
                ]),
            ])))
            root.addChildNode(mote)
        }
        root.categoryBitMask = 1
        return root
    }

    // MARK: - Nhím Tím (the pet, raised by activity)

    /// Chubby purple hedgehog matching the 2D mascot's palette — sphere
    /// body, cone spikes, bead eyes. Scale follows the user's level.
    private static func hedgehogNode(level: Int, streak: Int, animated: Bool) -> SCNNode {
        let purple = UIColor(red: 0x7A / 255.0, green: 0x55 / 255.0, blue: 0xC6 / 255.0, alpha: 1)
        let purpleDeep = UIColor(red: 0x5E / 255.0, green: 0x44 / 255.0, blue: 0xA0 / 255.0, alpha: 1)
        let facePale = UIColor(red: 0xE3 / 255.0, green: 0xD8 / 255.0, blue: 0xF7 / 255.0, alpha: 1)
        let ink = UIColor(red: 0x2A / 255.0, green: 0x1F / 255.0, blue: 0x45 / 255.0, alpha: 1)

        func matte(_ color: UIColor, gloss: CGFloat = 0.15) -> SCNMaterial {
            // Lambert, not PBR: the pet must read as a soft toy under any
            // light rig, and lambert takes the diffuse color literally.
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = color
            m.specular.contents = UIColor(white: CGFloat(gloss), alpha: 1)
            return m
        }

        let root = SCNNode()

        // body: chubby oval, snout toward +z
        let body = SCNNode(geometry: SCNSphere(radius: 0.085))
        body.geometry?.firstMaterial = matte(purple)
        body.scale = SCNVector3(1.0, 0.88, 1.22)
        body.position.y = 0.078
        root.addChildNode(body)

        // pale face mask (front-lower half sphere, inset)
        let face = SCNNode(geometry: SCNSphere(radius: 0.052))
        face.geometry?.firstMaterial = matte(facePale)
        face.position = SCNVector3(0, 0.062, 0.062)
        face.scale = SCNVector3(1.0, 0.9, 1.05)
        root.addChildNode(face)

        // snout + nose
        let nose = SCNNode(geometry: SCNSphere(radius: 0.011))
        nose.geometry?.firstMaterial = matte(ink, gloss: 0.5)
        nose.position = SCNVector3(0, 0.055, 0.125)
        root.addChildNode(nose)

        // eyes: black beads with a white glint
        for side in [-1.0, 1.0] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.0105))
            eye.geometry?.firstMaterial = matte(ink, gloss: 0.6)
            eye.position = SCNVector3(Float(side) * 0.028, 0.082, 0.098)
            root.addChildNode(eye)
            let glint = SCNNode(geometry: SCNSphere(radius: 0.0035))
            glint.geometry?.firstMaterial = matte(.white, gloss: 0.8)
            glint.position = SCNVector3(Float(side) * 0.024, 0.087, 0.107)
            root.addChildNode(glint)
        }

        // spikes: cones over the back hemisphere, pointing outward
        let spikeMat = matte(purpleDeep)
        for i in 0..<26 {
            // deterministic scatter over the back (no randomness — resume-safe)
            let u = Double(i % 7) / 6.0            // around
            let v = Double(i / 7) / 3.0            // front-to-back rows
            let theta = (0.15 + 0.7 * u) * .pi     // avoid the face
            let phi = (0.42 + 0.4 * v) * .pi       // upper back
            let dir = SCNVector3(
                Float(sin(phi) * cos(theta)),
                Float(cos(phi) * 0.9),
                Float(-sin(phi) * sin(theta)) * 1.1
            )
            let spike = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.014, height: 0.055))
            spike.geometry?.firstMaterial = spikeMat
            spike.position = SCNVector3(
                body.position.x + dir.x * 0.075,
                body.position.y + dir.y * 0.070,
                body.position.z + dir.z * 0.085
            )
            // cones point +y by default; align to the outward direction
            spike.look(at: SCNVector3(spike.position.x + dir.x, spike.position.y + dir.y, spike.position.z + dir.z),
                       up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, 1, 0))
            root.addChildNode(spike)
        }

        // feet: four little stubs
        for (dx, dz) in [(-0.035, 0.05), (0.035, 0.05), (-0.04, -0.03), (0.04, -0.03)] {
            let foot = SCNNode(geometry: SCNSphere(radius: 0.016))
            foot.geometry?.firstMaterial = matte(purpleDeep)
            foot.position = SCNVector3(Float(dx), 0.012, Float(dz))
            foot.scale = SCNVector3(1, 0.6, 1.2)
            root.addChildNode(foot)
        }

        // Wardrobe — unlocked by streak (same milestones the celebrations
        // use), cumulative: a long streak means a fully-kitted hedgehog.
        if streak >= 3 {
            // green runner scarf around the neck, with a dangling tail
            let scarf = SCNNode(geometry: SCNTorus(ringRadius: 0.052, pipeRadius: 0.012))
            scarf.geometry?.firstMaterial = matte(UIColor(red: 0.20, green: 0.70, blue: 0.49, alpha: 1), gloss: 0.2)
            scarf.position = SCNVector3(0, 0.088, 0.045)
            scarf.eulerAngles.x = 0.45
            root.addChildNode(scarf)
            let tail = SCNNode(geometry: SCNBox(width: 0.02, height: 0.05, length: 0.008, chamferRadius: 0.004))
            tail.geometry?.firstMaterial = scarf.geometry?.firstMaterial
            tail.position = SCNVector3(0.035, 0.055, 0.09)
            tail.eulerAngles.z = -0.25
            root.addChildNode(tail)
        }
        if streak >= 7 {
            // orange runner headband
            let band = SCNNode(geometry: SCNTorus(ringRadius: 0.047, pipeRadius: 0.009))
            band.geometry?.firstMaterial = matte(UIColor(red: 0.91, green: 0.51, blue: 0.29, alpha: 1), gloss: 0.2)
            band.position = SCNVector3(0, 0.125, 0.035)
            band.eulerAngles.x = -0.55
            root.addChildNode(band)
        }
        if streak >= 14 {
            // sunglasses 😎
            let lensMat = matte(ink, gloss: 0.75)
            for side in [-1.0, 1.0] {
                let lens = SCNNode(geometry: SCNCylinder(radius: 0.016, height: 0.005))
                lens.geometry?.firstMaterial = lensMat
                lens.position = SCNVector3(Float(side) * 0.028, 0.084, 0.104)
                lens.eulerAngles.x = .pi / 2 - 0.15
                root.addChildNode(lens)
            }
            let bridge = SCNNode(geometry: SCNBox(width: 0.026, height: 0.005, length: 0.005, chamferRadius: 0.002))
            bridge.geometry?.firstMaterial = lensMat
            bridge.position = SCNVector3(0, 0.088, 0.106)
            root.addChildNode(bridge)
        }
        if streak >= 30 {
            // hero cape (deep purple, flares out behind the spikes)
            let cape = SCNNode(geometry: SCNPlane(width: 0.1, height: 0.12))
            let capeMat = matte(UIColor(red: 0.29, green: 0.19, blue: 0.55, alpha: 1), gloss: 0.15)
            capeMat.isDoubleSided = true
            cape.geometry?.firstMaterial = capeMat
            cape.position = SCNVector3(0, 0.07, -0.085)
            cape.eulerAngles.x = 0.35
            root.addChildNode(cape)
        }
        if streak >= 50 {
            // flame halo — the legendary tier
            let halo = SCNNode(geometry: SCNTorus(ringRadius: 0.035, pipeRadius: 0.006))
            let haloMat = SCNMaterial()
            haloMat.lightingModel = .constant
            haloMat.emission.contents = UIColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1)
            halo.geometry?.firstMaterial = haloMat
            halo.position = SCNVector3(0, 0.185, 0.01)
            if animated {
                halo.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 4)))
            }
            root.addChildNode(halo)
        }

        // crown from level 10 — the "đã nuôi lớn" badge
        if level >= 10 {
            let gold = matte(UIColor(red: 0xF5 / 255.0, green: 0xC9 / 255.0, blue: 0x7B / 255.0, alpha: 1), gloss: 0.6)
            let band = SCNNode(geometry: SCNTube(innerRadius: 0.020, outerRadius: 0.026, height: 0.014))
            band.geometry?.firstMaterial = gold
            band.position = SCNVector3(0, 0.155, 0.028)
            band.eulerAngles.x = -0.35
            root.addChildNode(band)
            for k in 0..<3 {
                let point = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.006, height: 0.018))
                point.geometry?.firstMaterial = gold
                let angle = Float(k - 1) * 0.75
                point.position = SCNVector3(sin(angle) * 0.023, 0.168, 0.028 + cos(angle) * 0.008)
                point.eulerAngles.x = -0.35
                root.addChildNode(point)
            }
        }

        // Growth: level feeds size. Level 2 ≈ bé xíu, level 25+ ≈ mập ú.
        let growth = 0.72 + 0.045 * Double(min(max(level, 1), 25))
        root.scale = SCNVector3(Float(growth), Float(growth), Float(growth))

        if animated {
            // idle bob — alive, not busy
            root.runAction(.repeatForever(.sequence([
                .moveBy(x: 0, y: 0.012, z: 0, duration: 0.9),
                .moveBy(x: 0, y: -0.012, z: 0, duration: 0.9),
            ])))
        }
        return root
    }

    /// Solid part + wireframe hologram twin.
    private static func part(
        _ profile: [(t: Double, r: Double)],
        aspect: Double,
        x: Float,
        waistScale: Double = 1,
        hipScale: Double = 1
    ) -> SCNNode {
        let node = SCNNode(geometry: loft(profile, aspect: aspect, waistScale: waistScale, hipScale: hipScale))
        node.geometry?.firstMaterial = solidMaterial()
        node.position.x = x
        return node
    }

    private static func scales(waistCm: Double, hipCm: Double, heightCm: Double) -> (Double, Double) {
        let height = max(heightCm, 1)
        // circumference → semi-major axis (breadth/2), as fraction of height
        let waistSemi = (waistCm / perimeterFactor) / height
        let hipSemi = (hipCm / perimeterFactor) / height
        return (
            clamp(waistSemi / 0.078, 0.65, 1.7),
            clamp(hipSemi / 0.094, 0.65, 1.7)
        )
    }

    /// Vertical teal→purple gradient for the hologram skin.
    private static let holoGradient: UIImage = {
        let size = CGSize(width: 8, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.24, green: 0.86, blue: 0.72, alpha: 1).cgColor, // mint-teal (bottom)
                UIColor(red: 0.32, green: 0.72, blue: 0.86, alpha: 1).cgColor, // cyan
                UIColor(red: 0.54, green: 0.45, blue: 0.90, alpha: 1).cgColor, // violet (top)
            ]
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors as CFArray, locations: [0, 0.5, 1])!
            cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: size.height),
                                  end: CGPoint(x: 0, y: 0), options: [])
        }
    }()

    /// Two cute anime bead-eyes on the head front (spins with the figure).
    private static func faceEyes() -> SCNNode {
        let root = SCNNode()
        let ink = UIColor(red: 0x24 / 255.0, green: 0x1B / 255.0, blue: 0x3A / 255.0, alpha: 1)
        func flat(_ c: UIColor, glow: CGFloat = 0) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = c
            if glow > 0 {
                m.emission.contents = c
                m.emission.intensity = glow
            }
            return m
        }
        for side in [-1.0, 1.0] {
            // white base (oval, hugged to the head) + dark pupil + tiny glint
            let white = SCNNode(geometry: SCNSphere(radius: 0.019))
            white.geometry?.firstMaterial = flat(.white, glow: 0.25)
            white.position = SCNVector3(Float(side) * 0.030, 0.402, 0.056)
            white.scale = SCNVector3(0.85, 1.2, 0.55)
            root.addChildNode(white)

            let pupil = SCNNode(geometry: SCNSphere(radius: 0.0115))
            pupil.geometry?.firstMaterial = flat(ink)
            pupil.position = SCNVector3(Float(side) * 0.030, 0.400, 0.070)
            pupil.scale = SCNVector3(1, 1.15, 1)
            root.addChildNode(pupil)

            let glint = SCNNode(geometry: SCNSphere(radius: 0.004))
            glint.geometry?.firstMaterial = flat(.white, glow: 0.6)
            glint.position = SCNVector3(Float(side) * 0.030 + 0.004, 0.406, 0.079)
            root.addChildNode(glint)
        }
        return root
    }

    private static func solidMaterial() -> SCNMaterial {
        // Solid cel-shaded "anime" body — the same treatment as the hedgehog
        // pet (lambert-ish + a soft gradient skin), lit by the key light for
        // form and the green/purple rim lights for that glowing edge. Opaque
        // and cute, not a ghostly wireframe. A gentle self-emission keeps the
        // shadows from going dark so it stays a bright toon character. Still a
        // stylised silhouette (no face, no photoreal mesh) — privacy (#7) and
        // no-body-judgement (#4) hold.
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = holoGradient // teal→violet skin, UV-mapped
        m.emission.contents = holoGradient
        m.emission.intensity = 0.30
        m.specular.contents = UIColor(white: 0.55, alpha: 1)
        m.shininess = 0.32
        m.transparency = 1.0
        m.isDoubleSided = false
        m.writesToDepthBuffer = true
        return m
    }

    /// Lofted ellipse rings along a profile's t-range. Radii near the waist
    /// and hip rows get pulled toward the user's real semi-axes.
    private static func loft(
        _ profile: [(t: Double, r: Double)],
        aspect: Double,
        waistScale: Double,
        hipScale: Double,
        slices: Int = 64,
        segments: Int = 36
    ) -> SCNGeometry {
        let tStart = profile.first!.t
        let tEnd = profile.last!.t
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        var radii: [Double] = []
        var ts: [Double] = []
        for i in 0...slices {
            let t = tStart + (tEnd - tStart) * Double(i) / Double(slices)
            var r = interpolatedRadius(profile, at: t)
            // Gaussian-weighted pull toward the measured waist/hip.
            r *= 1 + (waistScale - 1) * gauss(t, center: waistRow, sigma: 0.055)
            r *= 1 + (hipScale - 1) * gauss(t, center: hipRow, sigma: 0.055)
            radii.append(r)
            ts.append(t)
        }

        for i in 0...slices {
            let r = radii[i]
            let y = Float(0.5 - ts[i]) // 1.0 tall, crown at +0.5
            // slope for shading (how fast the radius changes down the body)
            let slope = i == 0 || i == slices
                ? 0.0
                : (radii[i - 1] - radii[i + 1]) * Double(slices)
            for s in 0...segments {
                let theta = Double(s) / Double(segments) * 2 * .pi
                let x = Float(r * cos(theta))
                let z = Float(r * aspect * sin(theta))
                vertices.append(SCNVector3(x, y, z))
                let n = SCNVector3(
                    Float(cos(theta)),
                    Float(-slope * 0.8),
                    Float(sin(theta))
                )
                normals.append(normalized(n))
                // v maps head(t=0)→top of the gradient image, feet(t=1)→bottom.
                uvs.append(CGPoint(x: Double(s) / Double(segments), y: ts[i]))
            }
        }

        let ringSize = Int32(segments + 1)
        for i in 0..<Int32(slices) {
            for s in 0..<Int32(segments) {
                let a = i * ringSize + s
                let b = a + ringSize
                indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
            }
        }

        return SCNGeometry(
            sources: [
                SCNGeometrySource(vertices: vertices),
                SCNGeometrySource(normals: normals),
                SCNGeometrySource(textureCoordinates: uvs),
            ],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
    }

    private static func interpolatedRadius(_ profile: [(t: Double, r: Double)], at t: Double) -> Double {
        guard let upper = profile.firstIndex(where: { $0.t >= t }) else { return profile.last!.r }
        if upper == 0 { return profile[0].r }
        let (t0, r0) = profile[upper - 1]
        let (t1, r1) = profile[upper]
        let k = (t - t0) / max(t1 - t0, 0.0001)
        // smoothstep for organic transitions between control rows
        let smooth = k * k * (3 - 2 * k)
        return r0 + (r1 - r0) * smooth
    }

    private static func gauss(_ t: Double, center: Double, sigma: Double) -> Double {
        exp(-pow(t - center, 2) / (2 * sigma * sigma))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, v))
    }

    private static func normalized(_ v: SCNVector3) -> SCNVector3 {
        let len = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
        guard len > 0 else { return SCNVector3(0, 1, 0) }
        return SCNVector3(v.x / len, v.y / len, v.z / len)
    }
}
