import SwiftUI

/// Lengths of the focus timer's phases and what happens between them.
struct PomodoroPane: View {
    @Bindable var store: SettingsStore
    let module: PomodoroModule?

    var body: some View {
        SettingsForm {
            if let module {
                Section(L("settings.pomodoro.status", "Now")) {
                    StatusRow(
                        tone: module.timer.isRunning ? .ok : (module.timer.phase == .idle ? .neutral : .pending),
                        title: PomodoroRules.title(for: module.timer.phase),
                        detail: module.timer.phase == .idle ? nil : PomodoroRules.format(module.timer.remaining()) + " · " + L("settings.pomodoro.status.done", "\(module.timer.snapshot.completedWorkCount) focus blocks done")
                    )
                }
            }

            Section(L("settings.pomodoro.lengths", "Lengths")) {
                minutes(L("settings.pomodoro.work", "Focus"), value: $store.pomodoroWorkMinutes, range: SettingsRules.pomodoroWorkRange, step: 5)
                minutes(L("settings.pomodoro.break", "Short break"), value: $store.pomodoroBreakMinutes, range: SettingsRules.pomodoroBreakRange, step: 1)
                minutes(L("settings.pomodoro.longBreak", "Long break"), value: $store.pomodoroLongBreakMinutes, range: SettingsRules.pomodoroLongBreakRange, step: 5)
                Stepper(value: $store.pomodoroLongBreakEvery, in: SettingsRules.pomodoroLongBreakEveryRange) {
                    LabeledContent(L("settings.pomodoro.every", "Long break every")) {
                        Text(L("settings.pomodoro.every.value", "\(store.pomodoroLongBreakEvery) blocks"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(L("settings.pomodoro.behaviour", "Between phases")) {
                Toggle(L("settings.pomodoro.autoStart", "Start the next phase automatically"), isOn: $store.pomodoroAutoStart)
                    .toggleStyle(.switch)
                Toggle(L("settings.pomodoro.sound", "Chime when a phase ends"), isOn: $store.pomodoroSoundEnabled)
                    .toggleStyle(.switch)
                HStack {
                    Button(L("settings.pomodoro.reset", "Reset to 25 / 5 / 15")) {
                        store.resetPomodoro()
                    }
                    .controlSize(.small)
                    Spacer()
                }
                SettingsFootnote(L("settings.pomodoro.help", "The timer lives in the notch: hover to see the ring, tap the card to start, pause, skip or reset. A running cycle survives a relaunch."))
            }
        }
    }

    private func minutes(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        ValueSlider(
            title: title,
            value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step),
            format: { Duration.seconds(Int($0) * 60).formatted(.units(allowed: [.minutes], width: .abbreviated)) }
        )
    }
}
