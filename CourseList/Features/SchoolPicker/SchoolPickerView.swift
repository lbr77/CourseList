import ConfigurableKit
import UIKit

@MainActor
final class SchoolPickerController: StackScrollController, UISearchResultsUpdating {
    private let onSelect: (TimetableImportSchool) -> Void
    private let onCreateTimetable: () -> Void
    private var searchText = ""

    static func makeController(
        onSelect: @escaping (TimetableImportSchool) -> Void,
        onCreateTimetable: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> UIViewController {
        let controller = SchoolPickerController(onSelect: onSelect, onCreateTimetable: onCreateTimetable)
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: controller,
            action: #selector(SchoolPickerController.cancelTapped)
        )
        controller.onCancel = onCancel
        return UINavigationController(rootViewController: controller)
    }

    private var onCancel: () -> Void = {}

    private init(
        onSelect: @escaping (TimetableImportSchool) -> Void,
        onCreateTimetable: @escaping () -> Void
    ) {
        self.onSelect = onSelect
        self.onCreateTimetable = onCreateTimetable
        super.init(nibName: nil, bundle: nil)
        title = "选择学校"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "选择学校"
        navigationItem.largeTitleDisplayMode = .never

        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.searchBar.placeholder = "搜索学校"
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    override func setupContentViews() {
        super.setupContentViews()
        rebuildContent()
    }

    @objc private func cancelTapped() {
        onCancel()
    }

    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        rebuildContent()
    }

    private var filteredSchools: [TimetableImportSchool] {
        let keyword = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if keyword.isEmpty {
            return timetableImportSchools
        }
        return timetableImportSchools.filter {
            "\($0.label) \($0.id) \($0.defaultImportURL)".lowercased().contains(keyword)
        }
    }

    private func rebuildContent() {
        guard isViewLoaded else { return }

        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        stackView.addArrangedSubview(SeparatorView())

        for object in schoolObjects() {
            let view = object.createView()
            stackView.addArrangedSubviewWithMargin(view)
            stackView.addArrangedSubview(SeparatorView())
        }

    }

    private func schoolObjects() -> [ConfigurableObject] {
        var objects: [ConfigurableObject] = []

        if filteredSchools.isEmpty {
            objects.append(
                ConfigurableObject(customView: {
                    let label = UILabel()
                    label.numberOfLines = 0
                    label.textAlignment = .center
                    label.font = .preferredFont(forTextStyle: .body)
                    label.textColor = .secondaryLabel
                    label.text = "没有找到匹配学校"
                    return label
                })
            )
        } else {
            objects.append(contentsOf: filteredSchools.map { school in
                ConfigurableObject(
                    icon: "building.columns",
                    title: school.label,
                    explain: school.defaultImportURL,
                    ephemeralAnnotation: .action { _ in
                        self.onSelect(school)
                    }
                )
            })
        }

        return objects
    }
}
