import SwiftUI
import UIKit

// UIDatePicker owns the continuous time wheels, including noon/midnight rollover.
// Its native time layout has no headings and uses unpadded hours in 12-hour mode.
struct NativeTimePicker: UIViewRepresentable {
    @Binding var hour: Int
    @Binding var minute: Int
    let use24Hour: Bool
    let isLight: Bool

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.minuteInterval = 1
        picker.accessibilityIdentifier = "alarmTimePicker"
        picker.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return picker
    }
    func updateUIView(_ picker: UIDatePicker, context: Context) {
        context.coordinator.parent = self
        let locale = Locale(identifier: use24Hour ? "en_GB" : "en_US")
        if picker.locale != locale { picker.locale = locale }
        picker.overrideUserInterfaceStyle = isLight ? .light : .dark
        let selected = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
        if selected.hour != hour || selected.minute != minute {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: picker.date)
            parts.hour = hour; parts.minute = minute; parts.second = 0
            if let date = Calendar.current.date(from: parts) { picker.setDate(date, animated: false) }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject {
        var parent: NativeTimePicker
        init(_ parent: NativeTimePicker) { self.parent = parent }
        @objc func changed(_ picker: UIDatePicker) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: picker.date)
            parent.hour = parts.hour ?? 0
            parent.minute = parts.minute ?? 0
        }
    }
}

struct LoopingProblemPicker: UIViewRepresentable {
    @Binding var count: Int
    let color: UIColor
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator
        picker.delegate = context.coordinator
        picker.accessibilityIdentifier = "mathProblemPicker"
        picker.accessibilityLabel = "Number of problems"
        picker.selectRow(Coordinator.middle + count - 1, inComponent: 0, animated: false)
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.color != color {
            context.coordinator.color = color
            picker.reloadAllComponents()
        }
        if picker.selectedRow(inComponent: 0) % 8 + 1 != count {
            picker.selectRow(Coordinator.middle + count - 1, inComponent: 0, animated: false)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate {
        static let middle = 8 * 500
        var parent: LoopingProblemPicker
        var color: UIColor
        init(_ parent: LoopingProblemPicker) { self.parent = parent; color = parent.color }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { 8 * 1001 }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 40 }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? { String(row % 8 + 1) }
        func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
            let label = (view as? UILabel) ?? UILabel()
            label.text = String(row % 8 + 1)
            label.accessibilityLabel = label.text
            label.textAlignment = .center
            label.textColor = color
            label.font = .systemFont(ofSize: 28, weight: .light)
            label.isAccessibilityElement = false
            return label
        }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.count = row % 8 + 1
            // Identical rows surround the new position, so recentering is invisible
            // and neither direction can run into an end after repeated use.
            pickerView.selectRow(Self.middle + row % 8, inComponent: 0, animated: false)
        }
    }
}
