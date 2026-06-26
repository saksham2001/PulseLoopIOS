import WidgetKit
import SwiftUI

/// Watch face complication showing steps ring and next task.
struct PulseLoopComplication: Widget {
    let kind: String = "PulseLoopComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
        }
        .configurationDisplayName("PulseLoop")
        .description("Steps and next task at a glance.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCorner
        ])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let steps: Int
    let stepsGoal: Int
    let nextTask: String
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), steps: 6200, stepsGoal: 10000, nextTask: "Team standup")
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), steps: 6200, stepsGoal: 10000, nextTask: "Team standup")
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900)))
        completion(timeline)
    }
}

struct ComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()
            Gauge(value: Double(entry.steps), in: 0...Double(entry.stepsGoal)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text("\(entry.steps / 1000)k")
                    .font(.caption2)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.green)
        }
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                    .font(.caption2)
                Text("\(entry.steps.formatted()) steps")
                    .font(.caption2.bold())
            }
            if !entry.nextTask.isEmpty {
                Text(entry.nextTask)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ProgressView(value: Double(entry.steps), total: Double(entry.stepsGoal))
                .tint(.green)
        }
    }

    private var inlineView: some View {
        HStack(spacing: 4) {
            Image(systemName: "figure.walk")
            Text("\(entry.steps.formatted()) steps")
        }
    }
}
