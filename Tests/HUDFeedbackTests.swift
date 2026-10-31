// SPDX-License-Identifier: GPL-3.0-or-later

import Testing
@testable import Notched

/// When a volume key makes the feedback sound, as on macOS: the sound
/// preference decides, Shift flips it, and Shift+Option is always silent.
@Suite("HUDFeedback")
struct HUDFeedbackTests {
    @Test("With no modifiers the system preference decides")
    func followsThePreference() {
        #expect(HUDFeedback.shouldPlay(preference: true, modifiers: []) == true)
        #expect(HUDFeedback.shouldPlay(preference: false, modifiers: []) == false)
    }

    @Test("Shift flips the preference")
    func shiftFlipsIt() {
        #expect(HUDFeedback.shouldPlay(preference: true, modifiers: [.shift]) == false)
        #expect(HUDFeedback.shouldPlay(preference: false, modifiers: [.shift]) == true)
    }

    @Test("A fine step is silent either way")
    func fineStepIsSilent() {
        #expect(HUDFeedback.shouldPlay(preference: true, modifiers: [.shift, .option]) == false)
        #expect(HUDFeedback.shouldPlay(preference: false, modifiers: [.shift, .option]) == false)
    }
}
