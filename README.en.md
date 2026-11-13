# Meeting Vault

Turn recorded meetings into a **searchable archive** and **reusable knowledge** — not a pile of summaries nobody opens again.

Small, file-based toolkit: a macOS clipboard watcher, an archive script with SHA-256 dedupe, an index builder, and a set of prompts that turn transcripts into five kinds of assets.

Open `会议处理.html` in your vault to see counts for unstarted, started, awaiting approval, disputed, and completed meetings. Copy a short instruction for a single transcript and send it to your file-capable AI. A second review is optional. Conflicting findings require a human decision before approval. Approved findings are saved in `knowledge/已确认/`.

The optional [macOS status panel](macos-panel/README.md#english) shows the review queue in a compact floating window, with a menu bar entry to restore it. It reads the same vault as the HTML dashboard.

## Why

Most teams record every meeting, store the transcript, and never read it again. The archive grows; the experience doesn't. This project is built around four ideas:

1. **Meeting log ≠ knowledge base.** A log grows linearly per meeting; knowledge converges per judgment.
2. **Five assets, not five summaries.** Methods, recurring problems, precedent library, open loops, decision log.
3. **Parameters, methods, logic.** Parameters expire in weeks; methods last years; logic lasts. Storing a parameter as a method destroys the page when the number changes.
4. **Decisions need follow-up.** Record outcomes and evidence so decisions can be reviewed later.

## Privacy

The optional watcher continuously reads the clipboard and saves matching text locally. Transcripts, indexes and logs may contain sensitive information. Use only with authorization, protect and back up the vault, and never commit real meeting data to a public repository. The toolkit has no built-in encryption or access control. Run `./bin/uninstall.sh` to stop the watcher. Detection can miss or misclassify text.

## Quick start

Obsidian is optional. Clipboard monitoring is macOS-only; Windows script compatibility has not been tested.

```bash
git clone https://github.com/EousBangbooo/meeting-vault.git
cd meeting-vault
export MEETING_KB="$HOME/MeetingVault"
./bin/setup.sh                 # creates ~/MeetingVault
./bin/install.sh               # macOS: clipboard watcher (optional)
./bin/archive.sh ~/Desktop/2026-11-12-retro.txt
python3 bin/reindex.py --root "$MEETING_KB" --out "$MEETING_KB/index"
```

## Layout

```
$MEETING_KB/
├── 会议处理.md        review status, evidence and accepted findings
├── 会议处理.html      visual queue and single-meeting review instructions
├── raw/meetings/      transcripts, append-only
├── inbox/             clipboard drop zone
├── index/             generated index + audit report
└── knowledge/         methods, problems, precedent, open loops, decisions
```

Plain files on purpose: readable in Obsidian, VS Code, or `grep`, and versionable with git. No database — the data should outlive any tool.

## Docs

- [Design principles](docs/principles.md)
- [Workflow](docs/workflow.md)
- [Extraction prompts](docs/prompts.md)

## License

MIT
