import 'package:phosphor_flutter/phosphor_flutter.dart';

class AppIcons {
  AppIcons._();

  // ── Navigation (26 px; regular unselected, fill selected) ────────────────
  static PhosphorIconData navLibrary(bool selected) => selected
      ? PhosphorIcons.musicNote(PhosphorIconsStyle.fill)
      : PhosphorIcons.musicNote();
  static PhosphorIconData navDownloads(bool selected) => selected
      ? PhosphorIcons.downloadSimple(PhosphorIconsStyle.fill)
      : PhosphorIcons.downloadSimple();
  static PhosphorIconData navSearch(bool selected) => selected
      ? PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.fill)
      : PhosphorIcons.magnifyingGlass();

  // ── Transport (28–32 px) ──────────────────────────────────────────────────
  static final PhosphorIconData play =
      PhosphorIcons.play(PhosphorIconsStyle.fill);
  static final PhosphorIconData pause =
      PhosphorIcons.pause(PhosphorIconsStyle.fill);
  static final PhosphorIconData skipBack =
      PhosphorIcons.skipBack(PhosphorIconsStyle.fill);
  static final PhosphorIconData skipForward =
      PhosphorIcons.skipForward(PhosphorIconsStyle.fill);
  static final PhosphorIconData playCircle =
      PhosphorIcons.playCircle(PhosphorIconsStyle.fill);
  static final PhosphorIconData pauseCircle =
      PhosphorIcons.pauseCircle(PhosphorIconsStyle.fill);

  // ── Playback state toggles ────────────────────────────────────────────────
  static final PhosphorIconData shuffle = PhosphorIcons.shuffle();
  static final PhosphorIconData shuffleFill =
      PhosphorIcons.shuffle(PhosphorIconsStyle.fill);
  static final PhosphorIconData repeat = PhosphorIcons.repeat();
  static final PhosphorIconData repeatFill =
      PhosphorIcons.repeat(PhosphorIconsStyle.fill);
  static final PhosphorIconData repeatOne = PhosphorIcons.repeatOnce();

  // ── Inline actions (20 px) ────────────────────────────────────────────────
  static final PhosphorIconData more = PhosphorIcons.dotsThree();
  static final PhosphorIconData close = PhosphorIcons.x();
  static final PhosphorIconData caretRight = PhosphorIcons.caretRight();
  static final PhosphorIconData share = PhosphorIcons.shareNetwork();
  static final PhosphorIconData edit = PhosphorIcons.pencilSimple();
  static final PhosphorIconData addToPlaylist = PhosphorIcons.listPlus();
  static final PhosphorIconData delete = PhosphorIcons.trash();
  static final PhosphorIconData add = PhosphorIcons.plus();
  static final PhosphorIconData plusCircle = PhosphorIcons.plusCircle();
  static final PhosphorIconData refresh = PhosphorIcons.arrowsClockwise();
  static final PhosphorIconData inspect = PhosphorIcons.sparkle();

  // ── Downloader / import ───────────────────────────────────────────────────
  static final PhosphorIconData downloadFill =
      PhosphorIcons.downloadSimple(PhosphorIconsStyle.fill);
  static final PhosphorIconData fileAudio = PhosphorIcons.fileAudio();
  static final PhosphorIconData musicNote = PhosphorIcons.musicNote();

  // ── Theme toggles ─────────────────────────────────────────────────────────
  static final PhosphorIconData themeSystem = PhosphorIcons.circleHalf();
  static final PhosphorIconData themeLight =
      PhosphorIcons.sun(PhosphorIconsStyle.fill);
  static final PhosphorIconData themeDark =
      PhosphorIcons.moon(PhosphorIconsStyle.fill);

  // ── Settings / profile ────────────────────────────────────────────────────
  static final PhosphorIconData settings = PhosphorIcons.gear();
  static final PhosphorIconData settingsFill =
      PhosphorIcons.gear(PhosphorIconsStyle.fill);
  static final PhosphorIconData person = PhosphorIcons.user();
  static final PhosphorIconData globe = PhosphorIcons.globe();
  static final PhosphorIconData compass = PhosphorIcons.compass();

  // ── Library ───────────────────────────────────────────────────────────────
  static final PhosphorIconData queue = PhosphorIcons.queue();
  static final PhosphorIconData scanDevice = PhosphorIcons.arrowsClockwise();
}
