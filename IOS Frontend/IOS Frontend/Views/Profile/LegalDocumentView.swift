//
//  LegalDocumentView.swift
//  IOS Frontend
//
//  Reading the privacy policy, terms, or licence.
//

import SwiftUI

/// One legal document, laid out to be read rather than scrolled past.
///
/// Headings are picked out of the source text rather than marked up, so the
/// documents in `LegalDocuments` stay readable as plain prose — which matters
/// when the same words have to be checked by somebody who does not read Swift.
struct LegalDocumentView: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 9) {
                            if let heading = section.heading {
                                Text(heading)
                                    .font(.system(size: 11, weight: .bold))
                                    .tracking(1.2)
                                    .foregroundStyle(timeOfDay.accent)
                            }
                            if !section.text.isEmpty {
                                Text(section.text)
                                    .font(.subheadline)
                                    .foregroundStyle(timeOfDay.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .homeTimeScreen(timeOfDay)
        }
    }
}
