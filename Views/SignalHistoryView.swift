import SwiftUI
import Charts

// Вспомогательная структура для точки графика
struct HistoryPoint: Identifiable {
    let id = UUID()
    let bssid: String
    let ssid: String
    let date: Date // Реальное время
    let signal: Int
    let color: Color
}

struct SignalHistoryView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    // Подготовка данных с реальным временем
    private var chartData: [HistoryPoint] {
        var points: [HistoryPoint] = []
        let now = Date()
        
        for network in viewModel.networks {
            if let history = viewModel.signalHistory[network.bssid] {
                // ИСПРАВЛЕНИЕ: Генерируем цвет локально
                let color = generateColor(for: network.bssid)
                let name = network.ssid.isEmpty ? network.bssid : network.ssid
                
                // history[0] - самое старое. history.last - сейчас.
                let totalPoints = history.count
                
                for (index, signal) in history.enumerated() {
                    // Смещение назад во времени
                    let offsetSeconds = Double(totalPoints - 1 - index) * viewModel.refreshInterval
                    let timestamp = now.addingTimeInterval(-offsetSeconds)
                    
                    points.append(HistoryPoint(
                        bssid: network.bssid,
                        ssid: name,
                        date: timestamp,
                        signal: signal,
                        color: color
                    ))
                }
            }
        }
        return points
    }
    
    // Динамический масштаб Y
    var yDomain: ClosedRange<Int> {
        let allSignals = chartData.map { $0.signal }
        guard let minS = allSignals.min(), let maxS = allSignals.max() else { return -100...(-20) }
        return (minS - 5)...(maxS + 5)
    }
    
    var body: some View {
        VStack {
            Chart {
                ForEach(chartData) { point in
                    // Логика отображения:
                    let isSelected = (viewModel.selectedBSSID == point.bssid)
                    let isSomethingSelected = (viewModel.selectedBSSID != nil)
                    
                    // Линии (Background / Foreground)
                    if isSelected || !isSomethingSelected {
                        // Основная линия
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Signal", point.signal)
                        )
                        .foregroundStyle(point.color)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: isSelected ? 3 : 2))
                    } else {
                        // Фоновая линия (Dimmed)
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Signal", point.signal)
                        )
                        .foregroundStyle(Color.gray.opacity(0.3))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                    
                    // Заливка (Area) только для выбранной
                    if isSelected {
                        AreaMark(
                            x: .value("Time", point.date),
                            y: .value("Signal", point.signal)
                        )
                        .foregroundStyle(LinearGradient(
                            colors: [point.color.opacity(0.3), point.color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                        .interpolationMethod(.monotone)
                    }
                    
                    // Точка и текст в конце графика (только для актуальных линий)
                    if (isSelected || !isSomethingSelected) && isLastPoint(point) {
                        PointMark(
                            x: .value("Time", point.date),
                            y: .value("Signal", point.signal)
                        )
                        .foregroundStyle(point.color)
                        .annotation(position: .trailing, alignment: .leading) {
                            Text("\(point.ssid) \(formatSignal(point.signal))")
                                .font(.caption2).bold()
                                .foregroundColor(point.color)
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            // Ось X (Время)
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    AxisTick()
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.hour().minute().second())
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            // Ось Y (Уровень)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            // Интерактивность (Selection)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let y = value.location.y
                                    if let date: Date = proxy.value(atX: value.location.x) {
                                        selectNetworkAt(date: date, y: y, proxy: proxy)
                                    }
                                }
                        )
                }
            }
            .padding(.trailing, 80) // Место под лейблы
            .padding(.top, 10)
            .padding(.bottom, 5)
            .padding(.leading, 10)
        }
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Helpers
    
    // Генератор цветов (аналогичен тому, что в SpectrumView)
    func generateColor(for bssid: String) -> Color {
        let hash = bssid.hashValue
        let hue = Double(abs(hash) % 1000) / 1000.0
        return Color(hue: hue, saturation: 0.8, brightness: 1.0)
    }
    
    func isLastPoint(_ point: HistoryPoint) -> Bool {
        return abs(point.date.timeIntervalSinceNow) < (viewModel.refreshInterval * 1.5)
    }
    
    func formatSignal(_ signal: Int) -> String {
        return viewModel.formatSignal(signal) + (viewModel.signalDisplayMode == .dbm ? " dBm" : "")
    }
    
    func selectNetworkAt(date: Date, y: CGFloat, proxy: ChartProxy) {
        let range = viewModel.refreshInterval / 2.0
        let candidates = chartData.filter { abs($0.date.timeIntervalSince(date)) < range }
        
        var bestMatch: String? = nil
        var minDistance: CGFloat = 50.0
        
        for point in candidates {
            if let pointY = proxy.position(forY: point.signal) {
                let dist = abs(pointY - y)
                if dist < minDistance {
                    minDistance = dist
                    bestMatch = point.bssid
                }
            }
        }
        
        viewModel.selectedBSSID = bestMatch
    }
}
