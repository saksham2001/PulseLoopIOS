import Foundation

// MARK: - Exercise Catalog

/// A static, comprehensive built-in exercise library seeded into SwiftData on
/// first launch. Mirrors the kind of catalog seen in dedicated strength apps:
/// 150+ exercises across muscle groups and equipment types.
enum ExerciseCatalog {
    struct Entry {
        let name: String
        let group: MuscleGroup
        let equipment: Equipment
        let instructions: String
    }

    /// Builds `Exercise` model instances from the static list.
    static func makeAll() -> [Exercise] {
        all.map { Exercise(name: $0.name, muscleGroup: $0.group, equipment: $0.equipment, instructions: $0.instructions, isCustom: false) }
    }

    static let all: [Entry] = chest + back + shoulders + arms + legs + glutes + core + fullBody + cardio

    // MARK: Chest

    static let chest: [Entry] = [
        Entry(name: "Bench Press", group: .chest, equipment: .barbell, instructions: "Lie on a flat bench, lower the bar to mid-chest, press up until arms are extended."),
        Entry(name: "Bench Press", group: .chest, equipment: .dumbbellDouble, instructions: "Press two dumbbells from chest level to full extension, keeping wrists stacked over elbows."),
        Entry(name: "Bench Press", group: .chest, equipment: .cableDouble, instructions: "Press both cable handles forward from chest height, squeezing the chest at the top."),
        Entry(name: "Incline Bench Press", group: .chest, equipment: .barbell, instructions: "On a 30–45° incline, press the bar from upper chest to lockout."),
        Entry(name: "Incline Bench Press", group: .chest, equipment: .dumbbellDouble, instructions: "On an incline, press dumbbells from upper chest to full extension."),
        Entry(name: "Decline Bench Press", group: .chest, equipment: .barbell, instructions: "On a decline bench, press the bar from lower chest to lockout."),
        Entry(name: "Chest Fly", group: .chest, equipment: .dumbbellDouble, instructions: "With a slight elbow bend, open arms wide then bring dumbbells together over the chest."),
        Entry(name: "Cable Crossover", group: .chest, equipment: .cableDouble, instructions: "From high pulleys, sweep both handles down and together in front of the hips."),
        Entry(name: "Cable Pullover", group: .chest, equipment: .cableSingle, instructions: "With straight arms, pull the cable from overhead down to the thighs."),
        Entry(name: "Pec Deck", group: .chest, equipment: .machine, instructions: "Bring the machine arms together in front of the chest, controlling the return."),
        Entry(name: "Push Up", group: .chest, equipment: .bodyweight, instructions: "Lower your chest to the floor keeping a straight line, then press back up."),
        Entry(name: "Box Push Up", group: .chest, equipment: .bodyweight, instructions: "Perform a push up with hands on a box to reduce range and load."),
        Entry(name: "Archer Push Up", group: .chest, equipment: .bodyweight, instructions: "Shift weight toward one arm while the other extends, then alternate."),
        Entry(name: "Bodyweight Fly", group: .chest, equipment: .bodyweight, instructions: "On sliders or rings, open and close the arms against bodyweight."),
        Entry(name: "Dips", group: .chest, equipment: .bodyweight, instructions: "Lean forward on parallel bars and lower until the shoulders dip below the elbows."),
    ]

    // MARK: Back

    static let back: [Entry] = [
        Entry(name: "Deadlift", group: .back, equipment: .barbell, instructions: "Hinge at the hips, grip the bar, and stand tall driving through the floor."),
        Entry(name: "Bent Over Row", group: .back, equipment: .barbell, instructions: "Hinge forward and row the bar to the lower ribs, squeezing the shoulder blades."),
        Entry(name: "Bent Over Row", group: .back, equipment: .cableSingle, instructions: "Hinged at the hips, row a single cable handle to the torso."),
        Entry(name: "Back Row", group: .back, equipment: .machine, instructions: "Seated at the machine, pull the handles to your torso and control the return."),
        Entry(name: "Cable Row", group: .back, equipment: .cableSingle, instructions: "Seated, pull the cable to your midsection keeping the chest tall."),
        Entry(name: "Lat Pulldown", group: .back, equipment: .cableSingle, instructions: "Pull the bar to the upper chest, driving the elbows down and back."),
        Entry(name: "Behind-the-Neck Lat Pulldown", group: .back, equipment: .cableSingle, instructions: "Pull the bar behind the neck with control; use light load."),
        Entry(name: "Pull Up", group: .back, equipment: .bodyweight, instructions: "From a dead hang, pull until the chin clears the bar."),
        Entry(name: "Assisted Pull Up", group: .back, equipment: .band, instructions: "Use a band for assistance and pull until the chin clears the bar."),
        Entry(name: "Assisted Pull Up", group: .back, equipment: .machineAssisted, instructions: "Use the assisted machine to complete full-range pull ups."),
        Entry(name: "Chin Up", group: .back, equipment: .bodyweight, instructions: "With a supinated grip, pull until the chin clears the bar."),
        Entry(name: "Assisted Chin Up", group: .back, equipment: .machineAssisted, instructions: "Use machine assistance for supinated-grip pull ups."),
        Entry(name: "Archer Row", group: .back, equipment: .band, instructions: "Row a band to one side while the other arm stays extended."),
        Entry(name: "Cable Pullover", group: .back, equipment: .cableSingle, instructions: "With straight arms, pull the cable from overhead to the hips, emphasising the lats."),
        Entry(name: "Cable Row", group: .back, equipment: .cableDouble, instructions: "Row both cable handles to the torso, squeezing the mid-back."),
        Entry(name: "Back Extension", group: .back, equipment: .bodyweight, instructions: "On a hyperextension bench, lower the torso then extend back to neutral."),
        Entry(name: "Pendlay Row", group: .back, equipment: .barbell, instructions: "From the floor each rep, explosively row the bar to the lower chest."),
        Entry(name: "T-Bar Row", group: .back, equipment: .machine, instructions: "Hinge over the T-bar and row the handles to the chest."),
    ]

    // MARK: Shoulders

    static let shoulders: [Entry] = [
        Entry(name: "Overhead Press", group: .shoulders, equipment: .barbell, instructions: "Press the bar from the front of the shoulders to overhead lockout."),
        Entry(name: "Arnold Press", group: .shoulders, equipment: .dumbbellDouble, instructions: "Rotate the dumbbells from palms-in to palms-out as you press overhead."),
        Entry(name: "Shoulder Press", group: .shoulders, equipment: .dumbbellDouble, instructions: "Press dumbbells from shoulder height to overhead."),
        Entry(name: "Shoulder Press", group: .shoulders, equipment: .machine, instructions: "Press the machine handles from shoulder height to overhead."),
        Entry(name: "Behind-the-Neck Shoulder Press", group: .shoulders, equipment: .smithMachine, instructions: "Lower the bar behind the neck then press to lockout; use light load."),
        Entry(name: "Lateral Raise", group: .shoulders, equipment: .dumbbellDouble, instructions: "Raise the dumbbells out to the sides to shoulder height with soft elbows."),
        Entry(name: "Lateral Raise", group: .shoulders, equipment: .cableSingle, instructions: "Raise a single cable handle out to the side to shoulder height."),
        Entry(name: "Bent Over Lateral Raise", group: .shoulders, equipment: .cableSingle, instructions: "Hinged forward, raise the cable out to the side targeting the rear delt."),
        Entry(name: "Bent Over Deltoid Raise", group: .shoulders, equipment: .dumbbellDouble, instructions: "Hinged forward, raise both dumbbells out and back for rear delts."),
        Entry(name: "Front Raise", group: .shoulders, equipment: .dumbbellDouble, instructions: "Raise the dumbbells straight in front to shoulder height."),
        Entry(name: "Face Pull", group: .shoulders, equipment: .rope, instructions: "Pull the rope to the face, flaring the elbows for rear delts and upper back."),
        Entry(name: "Upright Row", group: .shoulders, equipment: .barbell, instructions: "Pull the bar up the front of the body to chest height, elbows leading."),
        Entry(name: "Band Pull Apart", group: .shoulders, equipment: .band, instructions: "Hold the band in front and pull it apart, squeezing the shoulder blades."),
        Entry(name: "Arm Circles", group: .shoulders, equipment: .bodyweight, instructions: "Extend the arms and make controlled forward and backward circles."),
        Entry(name: "Around the Worlds", group: .shoulders, equipment: .dumbbellDouble, instructions: "Sweep the dumbbells from the hips around overhead and back."),
    ]

    // MARK: Arms

    static let arms: [Entry] = [
        Entry(name: "Bicep Curl", group: .arms, equipment: .barbell, instructions: "Curl the bar from the thighs to the shoulders keeping elbows pinned."),
        Entry(name: "Bicep Curl", group: .arms, equipment: .dumbbellDouble, instructions: "Curl both dumbbells to the shoulders, controlling the lowering."),
        Entry(name: "Bicep Curl", group: .arms, equipment: .cableSingle, instructions: "Curl a single cable handle to the shoulder keeping tension throughout."),
        Entry(name: "Bicep Curl", group: .arms, equipment: .band, instructions: "Stand on the band and curl the handles to the shoulders."),
        Entry(name: "Bicep Curl", group: .arms, equipment: .ezBar, instructions: "Curl the EZ bar to reduce wrist strain while training the biceps."),
        Entry(name: "Bicep Curl", group: .arms, equipment: .trx, instructions: "Lean back on the straps and curl your body toward your hands."),
        Entry(name: "Close Bicep Curl", group: .arms, equipment: .barbell, instructions: "Curl with a narrow grip to bias the outer biceps."),
        Entry(name: "Close Bicep Curl", group: .arms, equipment: .ezBar, instructions: "Use the inner grip of the EZ bar and curl to the shoulders."),
        Entry(name: "Hammer Curl", group: .arms, equipment: .dumbbellDouble, instructions: "Curl with a neutral grip to target the brachialis and forearms."),
        Entry(name: "Preacher Curl", group: .arms, equipment: .ezBar, instructions: "On a preacher bench, curl the bar from full stretch to contraction."),
        Entry(name: "Concentration Curl", group: .arms, equipment: .dumbbellSingle, instructions: "Seated, brace the elbow on the inner thigh and curl one dumbbell."),
        Entry(name: "Tricep Pushdown", group: .arms, equipment: .rope, instructions: "Push the rope down and apart, fully extending the elbows."),
        Entry(name: "Tricep Pushdown", group: .arms, equipment: .cableSingle, instructions: "Push the cable bar down to full extension keeping elbows pinned."),
        Entry(name: "Overhead Tricep Extension", group: .arms, equipment: .dumbbellSingle, instructions: "Lower one dumbbell behind the head then extend the elbows."),
        Entry(name: "Skull Crusher", group: .arms, equipment: .ezBar, instructions: "Lying down, lower the bar to the forehead then extend the elbows."),
        Entry(name: "Assisted Tricep Dip", group: .arms, equipment: .machineAssisted, instructions: "Use machine assistance to perform full-range tricep dips."),
        Entry(name: "Tricep Dip", group: .arms, equipment: .bodyweight, instructions: "On parallel bars staying upright, lower and press to train triceps."),
        Entry(name: "Behind-the-Back Wrist Curl", group: .arms, equipment: .barbell, instructions: "Hold the bar behind the back and curl the wrists for forearms."),
    ]

    // MARK: Legs

    static let legs: [Entry] = [
        Entry(name: "Back Squat", group: .legs, equipment: .barbell, instructions: "With the bar on the upper back, squat to depth then drive up."),
        Entry(name: "Front Squat", group: .legs, equipment: .barbell, instructions: "Rack the bar on the front delts and squat keeping the torso upright."),
        Entry(name: "Goblet Squat", group: .legs, equipment: .kettlebellSingle, instructions: "Hold a kettlebell at the chest and squat to depth."),
        Entry(name: "Leg Press", group: .legs, equipment: .machine, instructions: "Press the platform away until the legs are nearly straight, then return."),
        Entry(name: "Leg Extension", group: .legs, equipment: .machine, instructions: "Extend the knees against the pad, squeezing the quads at the top."),
        Entry(name: "Leg Curl", group: .legs, equipment: .machine, instructions: "Curl the pad toward the glutes, contracting the hamstrings."),
        Entry(name: "Romanian Deadlift", group: .legs, equipment: .barbell, instructions: "Hinge at the hips with soft knees, lowering the bar along the legs."),
        Entry(name: "Bulgarian Split Squat", group: .legs, equipment: .barbell, instructions: "With the rear foot elevated, lunge down on the front leg."),
        Entry(name: "Bulgarian Split Squat", group: .legs, equipment: .dumbbellDouble, instructions: "Holding dumbbells, lunge with the rear foot elevated."),
        Entry(name: "Bulgarian Split Squat", group: .legs, equipment: .band, instructions: "Use band tension while lunging with the rear foot elevated."),
        Entry(name: "Walking Lunge", group: .legs, equipment: .dumbbellDouble, instructions: "Step forward into a lunge, then drive up into the next step."),
        Entry(name: "Calf Raise", group: .legs, equipment: .bodyweight, instructions: "Rise onto the balls of the feet then lower under control."),
        Entry(name: "Calf Raise", group: .legs, equipment: .band, instructions: "With band tension, rise onto the balls of the feet."),
        Entry(name: "Calf Raises", group: .legs, equipment: .dumbbellDouble, instructions: "Holding dumbbells, rise onto the toes and lower slowly."),
        Entry(name: "Calf Raises", group: .legs, equipment: .machine, instructions: "On the machine, drive through the toes and lower under control."),
        Entry(name: "Calf Press", group: .legs, equipment: .band, instructions: "Press a band with the toes, extending through the ankle."),
        Entry(name: "Calf Press Machine", group: .legs, equipment: .machine, instructions: "On the calf press machine, push through the balls of the feet."),
        Entry(name: "Box Jump", group: .legs, equipment: .bodyweight, instructions: "Explosively jump onto a box and stand tall, then step down."),
    ]

    // MARK: Glutes

    static let glutes: [Entry] = [
        Entry(name: "Hip Thrust", group: .glutes, equipment: .barbell, instructions: "With shoulders on a bench, drive the bar up by extending the hips."),
        Entry(name: "Glute Bridge", group: .glutes, equipment: .bodyweight, instructions: "Lying down, drive the hips up and squeeze the glutes at the top."),
        Entry(name: "Butt Blaster", group: .glutes, equipment: .machine, instructions: "Press the platform back and up with one leg, squeezing the glute."),
        Entry(name: "Cable Kickback", group: .glutes, equipment: .cableSingle, instructions: "Kick one leg back against the cable, contracting the glute."),
        Entry(name: "Bottoms Up Clean", group: .glutes, equipment: .kettlebellSingle, instructions: "Clean the kettlebell to the rack with the bell inverted."),
    ]

    // MARK: Core

    static let core: [Entry] = [
        Entry(name: "Ab Crunch Machine", group: .core, equipment: .machine, instructions: "Crunch against the machine pad, contracting the abs."),
        Entry(name: "Ab Roller", group: .core, equipment: .other, instructions: "Roll the wheel out under control and contract the abs to return."),
        Entry(name: "Ab Rollout", group: .core, equipment: .trx, instructions: "Roll the straps out then pull back using the core."),
        Entry(name: "Bicycle Crunches", group: .core, equipment: .bodyweight, instructions: "Alternate bringing each elbow to the opposite knee."),
        Entry(name: "Bird Dog", group: .core, equipment: .bodyweight, instructions: "From all fours, extend opposite arm and leg keeping the spine neutral."),
        Entry(name: "Body Up", group: .core, equipment: .bodyweight, instructions: "From a forearm plank, press up to hands then return."),
        Entry(name: "Arch Hold", group: .core, equipment: .bodyweight, instructions: "Lying face down, lift the arms and legs and hold the arch."),
        Entry(name: "Back Plank", group: .core, equipment: .bodyweight, instructions: "Hold a reverse plank with hips lifted and body straight."),
        Entry(name: "Anti Rotation", group: .core, equipment: .landmine, instructions: "Resist rotation while moving the landmine across the body."),
        Entry(name: "Core Rotation", group: .core, equipment: .cableSingle, instructions: "Rotate the torso against the cable, bracing the core."),
        Entry(name: "Assisted Crunch", group: .core, equipment: .trx, instructions: "With feet in the straps, pull the knees to the chest."),
        Entry(name: "Arm Bar", group: .core, equipment: .kettlebellSingle, instructions: "Lying down, hold the kettlebell overhead and rotate to brace the core."),
        Entry(name: "Plank", group: .core, equipment: .bodyweight, instructions: "Hold a straight line on the forearms, bracing the abs and glutes."),
        Entry(name: "Russian Twist", group: .core, equipment: .bodyweight, instructions: "Seated and leaning back, rotate the torso side to side."),
    ]

    // MARK: Full Body

    static let fullBody: [Entry] = [
        Entry(name: "Burpee", group: .fullBody, equipment: .bodyweight, instructions: "Drop to a push up, jump the feet in, then leap up."),
        Entry(name: "Burpee", group: .fullBody, equipment: .trx, instructions: "Use the straps for support through the burpee sequence."),
        Entry(name: "Clean and Press", group: .fullBody, equipment: .barbell, instructions: "Pull the bar to the shoulders then press overhead."),
        Entry(name: "Thruster", group: .fullBody, equipment: .barbell, instructions: "Squat then drive up into an overhead press in one motion."),
        Entry(name: "Kettlebell Swing", group: .fullBody, equipment: .kettlebellSingle, instructions: "Hinge and swing the bell to chest height using the hips."),
        Entry(name: "Alternating Waves", group: .fullBody, equipment: .rope, instructions: "Whip the battle ropes in alternating waves."),
        Entry(name: "Butt Kicks", group: .fullBody, equipment: .bodyweight, instructions: "Jog in place kicking the heels to the glutes."),
        Entry(name: "Butt Up", group: .fullBody, equipment: .bodyweight, instructions: "From a plank, pike the hips up then return."),
        Entry(name: "Bottoms Up Clean", group: .fullBody, equipment: .kettlebellSingle, instructions: "Clean the kettlebell to the rack with the bell inverted."),
    ]

    // MARK: Cardio

    static let cardio: [Entry] = [
        Entry(name: "Assault Bike", group: .cardio, equipment: .bodyweight, instructions: "Drive arms and legs on the fan bike at a steady or interval pace."),
        Entry(name: "Box Jump", group: .cardio, equipment: .bodyweight, instructions: "Jump onto a box and stand tall, then step down and repeat."),
        Entry(name: "Jump Rope", group: .cardio, equipment: .other, instructions: "Skip the rope with small, quick wrist turns."),
        Entry(name: "Rowing", group: .cardio, equipment: .machine, instructions: "Drive with the legs, lean back, then pull the handle to the ribs."),
        Entry(name: "High Knees", group: .cardio, equipment: .bodyweight, instructions: "Run in place driving the knees to hip height."),
        Entry(name: "Mountain Climbers", group: .cardio, equipment: .bodyweight, instructions: "From a plank, drive the knees to the chest alternately and quickly."),
    ]
}

