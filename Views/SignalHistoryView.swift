//
//  SignalHistoryView.swift
//

import SwiftUI
import Charts

struct SignalHistoryView: View {
    @ObservedObject var viewModel: AnalyzerViewModel
    
    // Состояние для интерактивности
    @State private var hoverLocation: CGPoint? = nil
    @State private var hoverIndex: Int? = nil
    
    // Константы масштаба
    private let minDbm: Double = -100
    private let maxDbm: Double = 0
    
    var body: some View {
        let isPercent = viewModel.signalDisplayMode == .percent
        
        // 1. Вычисляем пределы по оси X
        let maxDataPoints = viewModel.signalHistory.values.map { $0.count }.max() ?? 60
        // Добавляем 15% справа для подписей
        let xDomainMax = Int(Double(maxDataPoints) * 1.15)
        
        let minDomain = isPercent ? 0.0 : minDbm
        let maxDomain = isPercent ? 100.0 : maxDbm
        
        Chart {
            // ---------------------------
            // 1. ГРАФИКИ СЕТЕЙ
            // ---------------------------
            ForEach(viewModel.networks) { network in
                if let history = viewModel.signalHistory[network.bssid], !history.isEmpty {
                    
                    let isSelected = (viewModel.selectedBSSID == network.bssid)
                    let color = viewModel.colorFor(bssid: network.bssid)
                    
                    // Рисуем линию и заливку
                    ForEach(Array(history.enumerated()), id: \.offset) { index, signal in
                        SignalTrace(
                            x: .value("Time", index),
                            y: .value("Signal", isPercent ? viewModel.convertToPercent(signal) : Double(signal)),
                            yBase: .value("Base", minDomain),
                            traceID: network.bssid, // ID сети для правильного цвета линий
                            color: color,
                            isSelected: isSelected,
                            interpolation: .stepEnd
                        )
                    }
                    
                    // Рисуем подпись жестко справа
                    if let lastSignal = history.last {
                        PointMark(
                            x: .value("RightEdge", xDomainMax),
                            y: .value("Signal", isPercent ? viewModel.convertToPercent(lastSignal) : Double(lastSignal))
                        )
                        .symbolSize(0)
                        .annotation(position: .leading, alignment: .leading, spacing: 4) {
                            Text(network.ssid.isEmpty ? network.bssid : network.ssid)
                                .font(.caption2)
                                .fontWeight(isSelected ? .bold : .regular)
                                .foregroundColor(isSelected ? color : .gray)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            
            // ---------------------------
            // 2. КУРСОР И ТУЛТИПЫ
            // ---------------------------
            cursorOverlay(isPercent: isPercent, maxDataPoints: maxDataPoints)
        }
        // Настройки осей
        .chartYScale(domain: minDomain...maxDomain)
        .chartXScale(domain: 0...xDomainMax)
        .chartXAxis(.hidden)
        .chartYAxis {
            if isPercent {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue)%").font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
            } else {
                AxisMarks(position: .leading, values: [0, -20, -40, -60, -80, -100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4])).foregroundStyle(Color.gray.opacity(0.3))
                    AxisValueLabel {
                        if let intValue = value.as(Int.self) {
                            Text("\(intValue) dBm").font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        // СЛОЙ ВЗАИМОДЕЙСТВИЯ
        .chartOverlay { proxy in
            GeometryReader { geo in
                let frame = geo[proxy.plotAreaFrame]
                
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            updateCursor(at: location, proxy: proxy)
                        case .ended:
                            self.hoverLocation = nil
                            self.hoverIndex = nil
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                updateCursor(at: value.location, proxy: proxy)
                            }
                            .onEnded { value in
                                handleClick(at: value.location, proxy: proxy)
                            }
                    )
            }
        }
        .padding(.vertical)
        .padding(.leading)
        .padding(.trailing, 2)
        .background(Color.black.opacity(0.9))
    }
    
    // MARK: - Subviews & Builders
    
    @ChartContentBuilder
    private func cursorOverlay(isPercent: Bool, maxDataPoints: Int) -> some ChartContent {
        if let idx = hoverIndex {
            RuleMark(x: .value("Cursor", idx))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                .annotation(position: .top, alignment: .center) {
                    let secondsAgo = Int(viewModel.refreshInterval) * (maxDataPoints - 1 - idx)
                    Text(formatTimeAgo(seconds: secondsAgo))
                        .font(.caption2)
                        .padding(4)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(4)
                        .foregroundColor(.white)
                }
            
            if let selectedBSSID = viewModel.selectedBSSID,
               let history = viewModel.signalHistory[selectedBSSID],
               idx >= 0 && idx < history.count {
                
                let signal = history[idx]
                let val = isPercent ? viewModel.convertToPercent(signal) : Double(signal)
                let label = isPercent ? "\(Int(val))%" : "\(signal) dBm"
                let color = viewModel.colorFor(bssid: selectedBSSID)
                
                PointMark(
                    x: .value("Cursor", idx),
                    y: .value("Signal", val)
                )
                .symbol {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                }
                .annotation(position: .topLeading, spacing: 0) {
                    Text(label)
                        .font(.caption2.bold())
                        .padding(4)
                        .background(color)
                        .cornerRadius(4)
                        .foregroundColor(.white)
                        .offset(x: -10, y: -10)
                }
            }
        }
    }
    
    // MARK: - Interaction Logic
    
    private func updateCursor(at location: CGPoint, proxy: ChartProxy) {
        guard let index = proxy.value(atX: location.x, as: Int.self) else { return }
        self.hoverLocation = location
        self.hoverIndex = index
    }
    
    private func handleClick(at location: CGPoint, proxy: ChartProxy) {
        guard let index = proxy.value(atX: location.x, as: Int.self) else { return }
        self.hoverLocation = location
        self.hoverIndex = index
        
        guard let cursorYValue = proxy.value(atY: location.y, as: Double.self) else { return }
        
        let isPercent = viewModel.signalDisplayMode == .percent
        var bestMatch: String? = nil
        var minDiff: Double = Double.greatestFiniteMagnitude
        let tolerance = isPercent ? 20.0 : 15.0 // Зона чувствительности клика
        
        for network in viewModel.networks {
            if let history = viewModel.signalHistory[network.bssid],
               index >= 0, index < history.count {
                
                let rawSignal = history[index]
                let plotValue = isPercent ? viewModel.convertToPercent(rawSignal) : Double(rawSignal)
                let diff = abs(cursorYValue - plotValue)
                
                // Если кликнули близко к линии
                if diff < minDiff && diff < tolerance {
                    minDiff = diff
                    bestMatch = network.bssid
                }
            }
        }
        
        // ИЗМЕНЕНИЕ: Просто присваиваем bestMatch.
        // Если bestMatch == nil (клик в пустоту), то выделение сбросится.
        viewModel.selectedBSSID = bestMatch
    }
    
    private func formatTimeAgo(seconds: Int) -> String {
        if seconds < 0 { return "Future" }
        if seconds < 5 { return "Now" }
        let date = Date().addingTimeInterval(TimeInterval(-seconds))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Helper Component
struct SignalTrace<X: Plottable, Y: Plottable>: ChartContent {
    let x: PlottableValue<X>
    let y: PlottableValue<Y>
    let yBase: PlottableValue<Y>
    let traceID: String
    let color: Color
    let isSelected: Bool
    let interpolation: InterpolationMethod
    
    var body: some ChartContent {
        if isSelected {
            AreaMark(
                x: x,
                yStart: yBase,
                yEnd: y,
                series: .value("ID", traceID)
            )
            .interpolationMethod(interpolation)
            .foregroundStyle(color.opacity(0.4))
        }
        
        LineMark(
            x: x,
            y: y,
            series: .value("ID", traceID)
        )
        .interpolationMethod(interpolation)
        .foregroundStyle(color)
        .lineStyle(StrokeStyle(lineWidth: isSelected ? 3 : 1.5))
        .opacity(isSelected ? 1.0 : 0.5)
    }
}
