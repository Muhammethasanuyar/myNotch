import SwiftUI

/// Calendar access, how early the countdown appears, and which calendars count.
struct CalendarPane: View {
    @Bindable var store: SettingsStore
    let module: CalendarModule?

    var body: some View {
        if let module {
            content(service: module.service)
        } else {
            ContentUnavailableView(L("settings.calendar.missing", "The calendar module is not registered."), systemImage: "calendar")
        }
    }

    private func content(service: CalendarService) -> some View {
        SettingsForm {
            Section(L("settings.calendar.access", "Access")) {
                accessRow(service.access)
                HStack(spacing: 8) {
                    if service.access == .notDetermined {
                        Button(L("settings.calendar.grant", "Grant access…")) {
                            Task { await service.requestAccess() }
                        }
                    }
                    if service.access == .denied || service.access == .restricted {
                        Button(L("settings.calendar.openPrivacy", "Open Privacy Settings…")) {
                            SystemSettingsLink.open(SystemSettingsLink.calendars)
                        }
                    }
                    Button(L("settings.calendar.refresh", "Refresh")) {
                        service.refresh()
                    }
                }
                SettingsFootnote(L("settings.calendar.access.help", "Read-only. Events never leave this Mac; the notch shows the next few and their meeting links."))
            }

            Section(L("settings.calendar.timing", "Timing")) {
                ValueSlider(
                    title: L("settings.calendar.lead", "Show the countdown"),
                    value: Binding(get: { Double(store.calendarLeadMinutes) }, set: { store.calendarLeadMinutes = Int($0.rounded()) }),
                    range: Double(SettingsRules.calendarLeadRange.lowerBound)...Double(SettingsRules.calendarLeadRange.upperBound),
                    step: 1,
                    format: { L("settings.calendar.lead.value", "\(Int($0)) min before") }
                )
                Toggle(L("settings.calendar.alerts", "Popups five minutes before and at the start"), isOn: $store.calendarAlertsEnabled)
                    .toggleStyle(.switch)
            }

            Section(L("settings.calendar.calendars", "Calendars")) {
                if service.calendars.isEmpty {
                    SettingsFootnote(L("settings.calendar.calendars.none", "Grant access to pick calendars; until then every calendar counts."))
                } else {
                    ForEach(service.calendars, id: \.id) { calendar in
                        Toggle(isOn: calendarBinding(calendar.id)) {
                            HStack(spacing: 8) {
                                Circle().fill(calendar.color.color).frame(width: 9, height: 9)
                                Text(calendar.title)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    SettingsFootnote(L("settings.calendar.calendars.help", "With nothing selected, every calendar counts."))
                }
            }
        }
    }

    private func accessRow(_ access: CalendarAccess) -> some View {
        let (tone, title): (StatusTone, String) = switch access {
        case .authorized: (.ok, L("settings.calendar.access.ok", "Allowed"))
        case .notDetermined: (.neutral, L("settings.calendar.access.notAsked", "Not asked yet"))
        case .denied: (.problem, L("settings.calendar.access.denied", "Denied — allow MyNotch under Calendars"))
        case .restricted: (.problem, L("settings.calendar.access.restricted", "Restricted by a profile"))
        }
        return StatusRow(tone: tone, title: title)
    }

    /// Selected calendars are stored as ids; an empty list means all of them.
    private func calendarBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { store.calendarSelectedIDs.isEmpty || store.calendarSelectedIDs.contains(id) },
            set: { on in
                var ids = Set(store.calendarSelectedIDs)
                if ids.isEmpty { ids = Set(module?.service.calendars.map(\.id) ?? []) }
                if on { ids.insert(id) } else { ids.remove(id) }
                store.calendarSelectedIDs = ids.sorted()
            }
        )
    }
}
