# Sound guidance test

How to try Kokobubu without looking at the screen. Sound guidance is in Kokobubu Dev only; the TestFlight app does not
have it yet.

## What it does

- Beeps lead the camera to the step's control. The beep comes from the left or right ear, is higher when the control is
  above the middle of the picture and lower below it, and gets faster as the control comes nearer to the middle.
- At the middle the beeps stop, the phone taps once, and Kokobubu says "The target is straight ahead, about 40
  centimeters away." The distance is said only when LiDAR or a surface measured it.
- When the control leaves the picture, Kokobubu says which way to move the phone ("Turn the phone left"), at most every
  2.5 seconds, and repeats it every 6 seconds while it stays outside.
- Beeps and hints wait while Kokobubu reads a step, while the microphone is open, and while a check runs.
- With VoiceOver on, the hints are VoiceOver announcements (the user's own VoiceOver voice and speed). The marker is a
  VoiceOver element: "Target: Press Start", with the way to turn as its value. Its actions are "Where is it?" and
  "Say it again". "Where is it?" is also in the ⋯ menu for everyone.
- It turns on by itself while VoiceOver runs. Settings › Sound guidance turns it on without VoiceOver.
- In this mode the app asks the server for one more sentence per step: how to find the control by hand ("The round
  knob at the left end of the panel"). Muse Spark writes it from the same photo, in the same plan call. It is read after
  the step, said again when the control is straight ahead, and is the VoiceOver hint of the target. Apps without this
  mode don't ask for it, so their plans and costs stay the same.

Recognition stays with Meta's models; the guidance uses only ARKit geometry and the system voice (project rules,
Approved Exceptions, 2026-10-27).

## Part 1: the maintainer, eyes off the screen

1. On the iPhone: Settings › Accessibility › Accessibility Shortcut › VoiceOver. A triple press of the side button now
   turns VoiceOver on and off.
2. Put on headphones. Left and right are hard to hear from the phone's speaker.
3. Open Kokobubu Dev, turn on Settings › Sound guidance (the touch sentence is asked for when the plan is made, so the
   mode must be on before the question), and ask for a task on a real device, with VoiceOver still off.
4. When the first step appears, turn VoiceOver on, then tap the screen three times with three fingers: Screen Curtain
   turns the screen black. Close your eyes as well.
5. Follow the beeps until the phone taps. Then reach along the phone's line to the control.
6. Swipe to the target element and listen to it. Swipe up or down for the actions and double-tap "Where is it?".
7. Turn the phone away from the device. The control leaves the picture and Kokobubu says which way to turn.
8. Listen to the touch sentence after the step. Did it lead your hand to the right control?
9. Do the step, then find "I've done it" on the card with VoiceOver and double-tap it. Note where you got lost.
10. Three-finger triple-tap brings the screen back; triple-press the side button to end VoiceOver.

Write down:

- Could you find the control without looking? How long did it take?
- Did any voice talk over another (VoiceOver, the step, a hint)?
- Was the beep rate or pitch confusing, too loud or too quiet?
- Was the distance right?
- Was the touch sentence true for this device? Did it name something you could not feel?

## Part 2: a blind tester

Before the session:

- Ask for the tester's consent. Record audio or video only if both of you agree (California requires the consent of
  everyone on a recording).
- The tester uses their own VoiceOver settings. Do not change their speech rate.
- Use a device the tester knows, such as a microwave or a washing machine at home.
- Give one sentence on the sounds: "Left and right ears show the side, higher is up, faster is closer, a tap means it
  is straight ahead."

During the session, do not help unless the tester asks. Note:

- each moment the tester stopped or asked something
- which sound or sentence did not help
- whether the tester found the control after the tap
- what they would change

Keep the results without names or other personal details.

## Known limits

- The marker only says where the control is. Guiding the finger to it would need hand recognition, and Apple's
  recognition features are not allowed in this project (project rules, Approved Exceptions, 2026-10-27).
- The step text and VoiceOver can both speak when a new step appears; Part 1 checks how bad this is.
- Without LiDAR, or when the control's place was only guessed, no distance is said.
