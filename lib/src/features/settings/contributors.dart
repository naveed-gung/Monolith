// ── Contributors ─────────────────────────────────────────────────────────────
//
// If you contributed to Monolith, add an entry here.
// The main developer entry in developer_identity.dart is NOT the place to edit.
//
// Fields:
//   name         — your display name
//   role         — what you contributed (e.g. 'Bug fixes', 'UI polish')
//   githubHandle — optional, shown as a tappable link

class ContributorEntry {
  const ContributorEntry({
    required this.name,
    required this.role,
    this.githubHandle,
  });

  final String name;
  final String role;
  final String? githubHandle;
}

const List<ContributorEntry> contributors = [
  // Add your entry below this line:
  // ContributorEntry(name: 'Your Name', role: 'What you did', githubHandle: 'your-handle'),
];
