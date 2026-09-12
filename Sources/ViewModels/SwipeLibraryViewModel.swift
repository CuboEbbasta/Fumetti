import Foundation

/// Tiene traccia del "contesto" corrente (una cartella dell'albero) e di come muoversi tra
/// contesti. Regola di navigazione (vedi 07_LEGGIMI_NAVIGAZIONE.md per i dettagli):
///
/// - **verticale**: esplora il contenuto del contesto corrente (i suoi fumetti e sotto-cartelle,
///   mostrati insieme in una griglia scorrevole) — non cambia la posizione nell'albero.
/// - **orizzontale**: cambia contesto spostandosi tra "fratelli" (altri figli dello stesso
///   genitore), mantenendo la stessa profondità — es. da "Manga" a "Marvel", se entrambi sono
///   sottocartelle dirette della stessa cartella principale.
/// - **selezionare un elemento della griglia** (tocco): se è una sottocartella, il suo contenuto
///   diventa il nuovo contesto (si "entra"); se è un fumetto, si apre nel lettore.
/// - **toccare un segmento del percorso in basso**: si risale direttamente a quel livello.
///
/// Sempre basato sull'albero vero già scansionato una volta sola (non si riscansiona il
/// filesystem durante la navigazione): cambiare contesto significa solo cambiare quale
/// ComicFolder è "corrente", l'albero in memoria resta lo stesso.
@MainActor
final class SwipeLibraryViewModel: ObservableObject {
    @Published private(set) var containerFolder: ComicFolder
    private let rootFolder: ComicFolder
    private let progressStore: ReadingProgressStore

    init(rootFolder: ComicFolder, progressStore: ReadingProgressStore = .shared) {
        self.rootFolder = rootFolder
        self.containerFolder = rootFolder
        self.progressStore = progressStore
    }

    // MARK: - Continua a leggere (su tutta la libreria, non solo il contesto corrente)

    /// Fumetti in corso (iniziati, non finiti) in tutta la libreria, dal più recente. Non tiene
    /// conto di dove si trovano nell'albero: "continua a leggere" guarda sempre a tutto.
    var continueReadingComics: [ComicFile] {
        let inProgress = progressStore.progress.values.filter { !$0.isCompleted && $0.currentPage > 0 }
        let sortedPaths = inProgress
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
            .map(\.relativePath)
        let byPath = Dictionary(uniqueKeysWithValues: rootFolder.allComicsRecursive.map { ($0.relativePath, $0) })
        return sortedPaths.compactMap { byPath[$0] }
    }

    // MARK: - Contenuto del contesto corrente (asse verticale)

    var subContainers: [ComicFolder] { containerFolder.subfolders }
    var directComics: [ComicFile] { containerFolder.comics }
    var isEmpty: Bool { subContainers.isEmpty && directComics.isEmpty }

    // MARK: - Fratelli del contesto corrente (asse orizzontale)

    private var siblingContexts: [ComicFolder] {
        guard let parent = containerFolder.parent else { return [containerFolder] }
        return parent.subfolders
    }

    private var currentSiblingIndex: Int? {
        siblingContexts.firstIndex { $0.id == containerFolder.id }
    }

    var previousSiblingContext: ComicFolder? {
        guard let index = currentSiblingIndex, index > 0 else { return nil }
        return siblingContexts[index - 1]
    }

    var nextSiblingContext: ComicFolder? {
        guard let index = currentSiblingIndex, index + 1 < siblingContexts.count else { return nil }
        return siblingContexts[index + 1]
    }

    func moveToPreviousSiblingContext() {
        guard let previous = previousSiblingContext else { return }
        containerFolder = previous
    }

    func moveToNextSiblingContext() {
        guard let next = nextSiblingContext else { return }
        containerFolder = next
    }

    // MARK: - Cambio di profondità

    func enter(folder: ComicFolder) {
        containerFolder = folder
    }

    func goUp(to ancestor: ComicFolder) {
        containerFolder = ancestor
    }

    /// Percorso dalla radice al contesto corrente: ogni elemento è toccabile per risalire
    /// direttamente a quel livello.
    var breadcrumbPath: [ComicFolder] {
        var path: [ComicFolder] = []
        var node: ComicFolder? = containerFolder
        while let current = node {
            path.insert(current, at: 0)
            node = current.parent
        }
        return path
    }
}
