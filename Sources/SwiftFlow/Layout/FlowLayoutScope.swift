/// Subset of the graph an algorithm should arrange.
public enum FlowLayoutScope: Sendable, Hashable {
    case all
    case selected
    case nodeIDs(Set<String>, includingDescendants: Bool = false)
    case children(parentID: String?)
}
