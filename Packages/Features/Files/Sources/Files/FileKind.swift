import Foundation

/// Coarse grouping of files by type, for the "large files" list (CLAUDE.md §6.7).
public enum FileKind: String, Sendable, CaseIterable {
    case video, audio, image, archive, diskImage, document, other

    public init(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "mov", "mp4", "m4v", "mkv", "avi", "wmv", "webm", "mpg", "mpeg": self = .video
        case "mp3", "m4a", "wav", "aiff", "flac", "aac", "ogg": self = .audio
        case "jpg", "jpeg", "png", "heic", "tiff", "raw", "dng", "psd", "gif": self = .image
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz": self = .archive
        case "dmg", "iso", "img", "pkg", "xip": self = .diskImage
        case "pdf", "doc", "docx", "xls", "xlsx", "xlsm", "ppt", "pptx", "pages", "numbers", "key", "txt":
            self = .document
        default: self = .other
        }
    }
}
