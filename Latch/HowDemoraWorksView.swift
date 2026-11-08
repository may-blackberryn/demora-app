//
//  HowDemoraWorksView.swift
//  A read-only, four-page explainer in You → Help & guide
//  (docs/you-redesign.md §5.12, Y10). Static text and symbols only: it
//  reads and writes no state, starts nothing and replaces the old
//  interactive walkthrough.
//

import SwiftUI

struct HowDemoraWorksView: View {
    @AppAccent private var accent
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let body: String
    }

    // Built in-body so tr() follows the current language.
    private var pages: [Page] {
        [
            Page(id: 0, symbol: "hand.raised",
                 title: tr("Your past decision wins"),
                 body: tr("You set your rules when you're calm. Later, when an impulse says \"just this once\", the rule you chose still holds.")),
            Page(id: 1, symbol: "arrow.up.arrow.down",
                 title: tr("Stricter is quick, looser waits"),
                 body: tr("Making a rule stricter can apply right away. Making it looser waits through the wait you chose in Rules → Your waits.")),
            Page(id: 2, symbol: "hourglass",
                 title: tr("Changes wait in Changes"),
                 body: tr("A looser change waits in Changes on Today with its countdown. Until it lands nothing changes, and you can cancel it any time.")),
            Page(id: 3, symbol: "person.2",
                 title: tr("Ways to skip a wait"),
                 body: tr("A trusted contact, a password or a phrase can let a change apply early, but only for the kinds of change you allowed. Changes to them wait too. Set them up in You → Ways to skip a wait.")),
        ]
    }

    var body: some View {
        VStack(spacing: DemoraSpace.l) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    VStack(alignment: .leading, spacing: DemoraSpace.m) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(accent)
                            .accessibilityHidden(true)
                        Text(item.title)
                            .demoraType(.hero)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(item.body)
                            .demoraType(.body)
                            .foregroundStyle(Ink.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .paperCard(padding: DemoraSpace.xl)
                    .padding(.horizontal, DemoraSpace.pageGutter)
                    .tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(maxWidth: DemoraSpace.maxContentWidth)
            if page < pages.count - 1 {
                Button(tr("Next")) { withAnimation { page += 1 } }
                    .buttonStyle(DemoraPrimaryButtonStyle())
                    .padding(.horizontal, DemoraSpace.pageGutter)
                    .frame(maxWidth: DemoraSpace.maxContentWidth)
            }
        }
        .padding(.vertical, DemoraSpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("How Demora works"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
