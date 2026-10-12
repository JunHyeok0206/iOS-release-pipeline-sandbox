import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}

@main
struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TestWidget", provider: Provider()) { entry in
            Text(entry.date, style: .time)
        }
    }
}
