import SwiftUI
import UIKit

/// Homepage della libreria secondo la regola di navigazione (vedi 07_LEGGIMI_NAVIGAZIONE.md):
/// ogni schermata rappresenta UN contesto (una cartella).
///
/// - Verticale: scorre il contenuto del contesto corrente ("Continua a leggere" su tutta la
///   libreria, poi "Serie" e "Fumetti" del contesto corrente, in gruppi separati).
/// - Orizzontale: passa al contesto "fratello" successivo/precedente (stessa profondità, stesso
///   genitore) — sia con lo swipe sia con le frecce ai lati, per rendere l'interazione più chiara.
/// - Toccare una sottocartella: il suo contenuto diventa il nuovo contesto.
/// - Toccare un segmento del percorso in basso: si risale direttamente a quel livello.
/// - Tenere premuto su una copertina: segna come letto, nascondi (Incognito), statistiche.
struct SwipeLibraryView: View {
    @StateObject private var navModel: SwipeLibraryViewModel
    let libraryRootURL: URL
    let settings: AppSettings

    @State private var dragTranslation: CGSize = .zero
    @State private var openedComic: ComicFile?

    /// Quanto si intravede, in punti, di ogni fratello adiacente quando fermi.
    private let peekSize: CGFloat = 40

    init(rootFolder: ComicFolder, libraryRootURL: URL, settings: AppSettings) {
        _navModel = StateObject(wrappedValue: SwipeLibraryViewModel(rootFolder: rootFolder))
        self.libraryRootURL = libraryRootURL
        self.settings = settings
    }

    private var horizontalDrag: CGFloat {
        abs(dragTranslation.width) > abs(dragTranslation.height) ? dragTranslation.width : 0
    }

    private var navAnimation: Animation { .spring(response: 0.4, dampingFraction: 0.85) }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let previous = navModel.previousSiblingContext {
                    siblingPeek(previous)
                        .offset(x: -(proxy.size.width - peekSize) + horizontalDrag)
                }
                if let next = navModel.nextSiblingContext {
                    siblingPeek(next)
                        .offset(x: (proxy.size.width - peekSize) + horizontalDrag)
                }

                contentScrollView
                    .offset(x: horizontalDrag)

                // Frecce esplicite, oltre allo swipe: rendono l'interazione chiara anche senza
                // scoprirla per tentativi.
                VStack {
                    Spacer()
                    HStack {
                        if navModel.previousSiblingContext != nil {
                            navArrow(systemImage: "chevron.left") {
                                withAnimation(navAnimation) { navModel.moveToPreviousSiblingContext() }
                            }
                        }
                        Spacer()
                        if navModel.nextSiblingContext != nil {
                            navArrow(systemImage: "chevron.right") {
                                withAnimation(navAnimation) { navModel.moveToNextSiblingContext() }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    Spacer()
                }
            }
            .clipped()
            .simultaneousGesture(
                DragGesture(minimumDistance: 16)
                    .onChanged { value in dragTranslation = value.translation }
                    .onEnded { value in handleDragEnd(value.translation, containerWidth: proxy.size.width) }
            )
        }
        .navigationDestination(item: $openedComic) { comic in
            ReaderView(comic: comic, libraryRootURL: libraryRootURL, settings: settings)
        }
    }

    private func navArrow(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    // MARK: - Contenuto del contesto corrente

    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                breadcrumbView

                if !navModel.continueReadingComics.isEmpty {
                    sectionHeader(title: "Continua a leggere")
                    continueReadingRow
                }

                if navModel.isEmpty {
                    if navModel.continueReadingComics.isEmpty {
                        ContentUnavailableView("Vuota", systemImage: "tray")
                            .foregroundStyle(.white)
                            .padding(.top, 60)
                    }
                } else {
                    if !navModel.subContainers.isEmpty {
                        sectionHeader(title: "Serie")
                        containerGrid
                    }
                    if !navModel.directComics.isEmpty {
                        sectionHeader(title: "Fumetti")
                        comicGrid
                    }
                }
            }
            .padding()
            .padding(.bottom, 40)
        }
        .background(Color.black)
    }

    private var continueReadingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(navModel.continueReadingComics) { comic in
                    Button { openedComic = comic } label: {
                        ContinueReadingTile(comic: comic, libraryRootURL: libraryRootURL)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var breadcrumbView: some View {
        HStack(spacing: 4) {
            ForEach(Array(navModel.breadcrumbPath.enumerated()), id: \.element.id) { index, folder in
                Button {
                    navModel.goUp(to: folder)
                } label: {
                    Text(folder.name.isEmpty ? "Libreria" : folder.name)
                        .font(index == navModel.breadcrumbPath.count - 1 ? .title.bold() : .footnote)
                        .foregroundStyle(index == navModel.breadcrumbPath.count - 1 ? .white : .white.opacity(0.45))
                }
                .buttonStyle(.plain)
                if index < navModel.breadcrumbPath.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
        }
    }

    private var containerGrid: some View {
        TileGrid(items: navModel.subContainers) { folder in
            ContainerTile(folder: folder, libraryRootURL: libraryRootURL) {
                withAnimation(navAnimation) { navModel.enter(folder: folder) }
            }
        }
    }

    private var comicGrid: some View {
        TileGrid(items: navModel.directComics) { comic in
            ComicTile(comic: comic, libraryRootURL: libraryRootURL) {
                openedComic = comic
            }
        }
    }

    private func siblingPeek(_ folder: ComicFolder) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.25))
            Text(folder.name)
                .font(.title2.bold())
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleDragEnd(_ translation: CGSize, containerWidth: CGFloat) {
        let threshold = containerWidth * 0.22
        if abs(translation.width) > abs(translation.height) {
            if translation.width < -threshold, navModel.nextSiblingContext != nil {
                withAnimation(navAnimation) { navModel.moveToNextSiblingContext(); dragTranslation = .zero }
                return
            } else if translation.width > threshold, navModel.previousSiblingContext != nil {
                withAnimation(navAnimation) { navModel.moveToPreviousSiblingContext(); dragTranslation = .zero }
                return
            }
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            dragTranslation = .zero
        }
    }
}

// MARK: - Griglia a 3 colonne, righe incomplete centrate, identità basata sui dati veri

private struct TileGrid<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content
    private let columnCount = 3
    private let spacing: CGFloat = 24

    init(items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    /// Una riga della griglia, con un'identità derivata dagli ID veri degli elementi che
    /// contiene (non dalla posizione): è la correzione al bug delle copertine che si
    /// "sovrapponevano" cambiando cartella. Usare l'indice come identità (com'era prima) fa
    /// sì che SwiftUI consideri "la stessa riga" due righe in cartelle diverse che occupano
    /// semplicemente la stessa posizione (es. sempre "riga 1"), riciclando la vista — con la
    /// copertina già caricata della cartella precedente — invece di ricrearla da capo.
    private struct Row: Identifiable {
        let id: String
        let items: [Item]
    }

    private var rows: [Row] {
        stride(from: 0, to: items.count, by: columnCount).map { start in
            let rowItems = Array(items[start..<Swift.min(start + columnCount, items.count)])
            let rowID = rowItems.map { "\($0.id)" }.joined(separator: "|")
            return Row(id: rowID, items: rowItems)
        }
    }

    var body: some View {
        VStack(spacing: 26) {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: spacing) {
                        ForEach(row.items) { item in
                            content(item)
                                .frame(width: 190)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Tessere

private struct ContainerTile: View {
    let folder: ComicFolder
    let libraryRootURL: URL
    let onSelect: () -> Void
    @ObservedObject private var incognitoStore = IncognitoStore.shared
    @State private var cover: UIImage?

    private var isHidden: Bool { incognitoStore.isHidden(folder.relativePath) }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Group {
                    if let cover {
                        Image(uiImage: cover).resizable().scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07))
                            .overlay(Image(systemName: "books.vertical.fill").foregroundStyle(.white.opacity(0.4)))
                    }
                }
                .aspectRatio(0.68, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(isHidden ? 0.4 : 1)

                Text(folder.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(folder.totalComicCount) fumetti")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .task {
            guard let representative = folder.representativeComic else { return }
            cover = await CoverCache.coverImage(for: representative, libraryRootURL: libraryRootURL)
        }
        .contextMenu {
            Button {
                incognitoStore.toggleHidden(folder.relativePath)
            } label: {
                Label(isHidden ? "Mostra (togli da Incognito)" : "Nascondi cartella (Incognito)", systemImage: isHidden ? "eye" : "eye.slash")
            }
        }
    }
}

private struct ComicTile: View {
    let comic: ComicFile
    let libraryRootURL: URL
    let onSelect: () -> Void
    @ObservedObject private var progressStore = ReadingProgressStore.shared
    @ObservedObject private var incognitoStore = IncognitoStore.shared
    @State private var cover: UIImage?
    @State private var resolvedTitle: String?
    @State private var showStatistics = false

    private var progress: ReadingProgress? { progressStore.progress(for: comic.relativePath) }
    private var isFinished: Bool { progress?.isCompleted ?? false }
    private var isHidden: Bool { incognitoStore.isHidden(comic.relativePath) }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let cover {
                            Image(uiImage: cover).resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07))
                                .overlay(Image(systemName: "book.closed").foregroundStyle(.white.opacity(0.4)))
                        }
                    }
                    .aspectRatio(0.68, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(isHidden ? 0.4 : 1)

                    if isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .background(Circle().fill(.black.opacity(0.4)).padding(-2))
                            .padding(6)
                            .font(.caption)
                    }
                }
                Text(resolvedTitle ?? comic.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let progress, progress.fraction > 0 {
                    ProgressView(value: progress.fraction).tint(isFinished ? .green : .white)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            let source = libraryRootURL.appendingPathComponent(comic.relativePath)
            async let coverTask = CoverCache.coverImage(for: comic, libraryRootURL: libraryRootURL)
            async let metadataTask = ComicParsingService.readMetadata(for: comic, at: source)
            let (fetchedCover, fetchedMetadata) = await (coverTask, metadataTask)
            cover = fetchedCover
            resolvedTitle = fetchedMetadata.title
        }
        .contextMenu {
            Button {
                progressStore.setCompleted(!isFinished, relativePath: comic.relativePath, totalPages: progress?.totalPages ?? 0)
            } label: {
                Label(isFinished ? "Segna come da leggere" : "Segna come letto", systemImage: isFinished ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button {
                incognitoStore.toggleHidden(comic.relativePath)
            } label: {
                Label(isHidden ? "Mostra (togli da Incognito)" : "Nascondi (Incognito)", systemImage: isHidden ? "eye" : "eye.slash")
            }
            Button {
                showStatistics = true
            } label: {
                Label("Statistiche", systemImage: "chart.bar")
            }
        }
        .sheet(isPresented: $showStatistics) {
            ComicStatisticsView(comic: comic)
        }
    }
}

/// Tessera più piccola per "Continua a leggere" (che mostra fumetti di tutta la libreria, non
/// del contesto corrente): copertina, titolo, percentuale.
private struct ContinueReadingTile: View {
    let comic: ComicFile
    let libraryRootURL: URL
    @ObservedObject private var progressStore = ReadingProgressStore.shared
    @State private var cover: UIImage?
    @State private var resolvedTitle: String?

    private var progress: ReadingProgress? { progressStore.progress(for: comic.relativePath) }
    private let tileWidth: CGFloat = 110

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover {
                    Image(uiImage: cover).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07))
                }
            }
            .frame(width: tileWidth)
            .aspectRatio(0.68, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(resolvedTitle ?? comic.displayTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: tileWidth, alignment: .leading)

            if let progress, progress.fraction > 0 {
                HStack(spacing: 4) {
                    ProgressView(value: progress.fraction).tint(.white)
                    Text("\(Int(progress.fraction * 100))%")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .frame(width: tileWidth)
            }
        }
        .task {
            let source = libraryRootURL.appendingPathComponent(comic.relativePath)
            async let coverTask = CoverCache.coverImage(for: comic, libraryRootURL: libraryRootURL)
            async let metadataTask = ComicParsingService.readMetadata(for: comic, at: source)
            let (fetchedCover, fetchedMetadata) = await (coverTask, metadataTask)
            cover = fetchedCover
            resolvedTitle = fetchedMetadata.title
        }
    }
}
