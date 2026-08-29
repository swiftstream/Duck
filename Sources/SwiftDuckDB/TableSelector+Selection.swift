import SwifQL

extension TableSelector {
    public func callAsFunction<each SelectedColumn>(
        _ selectedColumns: repeat KeyPath<T, each SelectedColumn>
    ) -> Self where repeat each SelectedColumn: ColumnRepresentable {
        for column in repeat each selectedColumns {
            _ = columns(column)
        }
        return self
    }
}
