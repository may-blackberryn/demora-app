//
//  ContactsOverrideViews.swift
//  Trusted-contact override: Settings editor, the "ask a contact" gate in
//  the override flow, and the approval inbox for incoming requests.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Avatar rendering & editing

extension Color {
    /// Init from a "#RRGGBB" hex string; falls back to the accent color.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&v), s.count == 6 else {
            self = Ink.accent
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Unified contact identity (by Demora code)
// A Demora user carries one name + avatar whether they appear under "people who
// approve for you" (a TrustedContact) or "people you approve for" (a grant).
// Edits in either place mirror into a shared per-code store; these resolvers
// read it with sensible fallbacks so both lists agree.

/// Best display name for a Demora user: a locally chosen name, else a matching
/// trusted contact's name, else `fallback`.
@MainActor
func resolvedName(forCode code: String, model: AppModel, fallback: String) -> String {
    let custom = ContactsRelay.name(forCode: code)
    if !custom.isEmpty { return custom }
    if let c = model.state.overrides.contacts.first(where: { $0.latchUserCode == code }),
       !c.name.isEmpty { return c.name }
    return fallback
}

/// Best avatar for a Demora user: the per-code store, else a matching trusted
/// contact's avatar.
@MainActor
func resolvedAvatar(forCode code: String, model: AppModel) -> ContactAvatar? {
    if let a = ContactsRelay.avatar(forCode: code) { return a }
    return model.state.overrides.contacts.first(where: { $0.latchUserCode == code })?.avatar
}

/// Persist a name edit to the shared per-code store and mirror it onto a
/// matching trusted contact, so both lists stay in sync.
@MainActor
func syncContactName(_ name: String, forCode code: String, model: AppModel) {
    ContactsRelay.setName(name, forCode: code)
    if let c = model.state.overrides.contacts.first(where: { $0.latchUserCode == code }) {
        model.renameContact(id: c.id, to: name)
    }
}

/// Persist an avatar edit to the shared per-code store and mirror it onto a
/// matching trusted contact.
@MainActor
func syncContactAvatar(_ avatar: ContactAvatar?, forCode code: String, model: AppModel) {
    ContactsRelay.setAvatar(avatar, forCode: code)
    if let c = model.state.overrides.contacts.first(where: { $0.latchUserCode == code }) {
        model.setContactAvatar(id: c.id, avatar)
    }
}

/// Renders a contact's avatar (photo, emoji, or symbol+color) in a circle.
/// Falls back to a tinted symbol using the name's first letter context.
struct ContactAvatarView: View {
    let avatar: ContactAvatar?
    var fallbackSymbol = "person.fill"
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if let a = avatar, a.style == .photo,
               let data = a.imageData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if let a = avatar, a.style == .emoji, !a.emoji.isEmpty {
                Circle().fill(Color(hex: a.colorHex).opacity(0.18))
                Text(a.emoji).font(.system(size: size * 0.5))
            } else {
                symbolFill(avatar)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    @ViewBuilder private func symbolFill(_ a: ContactAvatar?) -> some View {
        let color = Color(hex: a?.colorHex ?? "")
        Circle().fill(color.opacity(0.18))
        Image(systemName: a?.symbol ?? fallbackSymbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
    }
}

/// A reusable editor section: pick photo / emoji / symbol+color (one of).
struct AvatarEditorView: View {
    @Binding var avatar: ContactAvatar
    @State private var pickerSource: ImagePickerSource?

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        Section {
            HStack {
                Spacer()
                ContactAvatarView(avatar: avatar, size: 80)
                Spacer()
            }
            Picker(tr("Avatar"), selection: $avatar.style) {
                Text(tr("Icon")).tag(ContactAvatar.Style.symbol)
                Text(tr("Emoji")).tag(ContactAvatar.Style.emoji)
                Text(tr("Photo")).tag(ContactAvatar.Style.photo)
            }
            .pickerStyle(.segmented)

            switch avatar.style {
            case .symbol:
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(ContactAvatar.symbolChoices, id: \.self) { sym in
                        Button { avatar.symbol = sym } label: {
                            Image(systemName: sym)
                                .font(.system(size: 18))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(avatar.symbol == sym
                                                 ? Color(hex: avatar.colorHex) : Ink.faint)
                                .background((avatar.symbol == sym
                                             ? Color(hex: avatar.colorHex).opacity(0.18)
                                             : Color.clear), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(ContactAvatar.colorChoices, id: \.self) { hex in
                        Button { avatar.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Ink.ink,
                                    lineWidth: avatar.colorHex == hex ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            case .emoji:
                TextField(tr("Type one emoji"), text: Binding(
                    get: { avatar.emoji },
                    set: { avatar.emoji = String($0.prefix(1)) }))
                    .font(.largeTitle)
                    .multilineTextAlignment(.center)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(["😀","😎","🥳","🤓","😴","🐶","🐱","🦊","🐻","🌟","🔥","🎮","📚","🎧","🍕","☕️","💪","🧠","❤️","🌈"], id: \.self) { e in
                        Button { avatar.emoji = e } label: {
                            Text(e).font(.system(size: 24))
                                .frame(width: 38, height: 38)
                                .background((avatar.emoji == e
                                             ? Ink.accent.opacity(0.18) : Color.clear),
                                            in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(ContactAvatar.colorChoices, id: \.self) { hex in
                        Button { avatar.colorHex = hex } label: {
                            Circle().fill(Color(hex: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Ink.ink,
                                    lineWidth: avatar.colorHex == hex ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            case .photo:
                Button {
                    pickerSource = ImagePickerSource(kind: .photoLibrary)
                } label: {
                    Label(avatar.imageData == nil ? tr("Choose a photo")
                                                  : tr("Change photo"),
                          systemImage: "photo")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        pickerSource = ImagePickerSource(kind: .camera)
                    } label: {
                        Label(tr("Take photo"), systemImage: "camera")
                    }
                }
                if avatar.imageData != nil {
                    Button(tr("Remove photo"), role: .destructive) {
                        avatar.imageData = nil
                    }
                }
            }
        } header: {
            Text(tr("Avatar"))
        }
        .sheet(item: $pickerSource) { src in
            Group {
                if src.kind == .camera {
                    // The camera's built-in crop can't pan vertically, so use
                    // our own free pan/zoom cropper after capture.
                    CameraCropPicker { image in
                        if let image { finalize(image) }
                    }
                } else {
                    // The library's native move-and-scale crop works well.
                    ContactImagePicker(sourceType: src.kind) { image in
                        finalize(image)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func finalize(_ image: UIImage) {
        if let thumb = ContactAvatar.thumbnail(from: image) {
            avatar.imageData = thumb
            avatar.style = .photo
        }
    }
}

/// Identifiable wrapper so a UIImagePickerController source type can drive a
/// `.sheet(item:)`.
struct ImagePickerSource: Identifiable {
    let id = UUID()
    let kind: UIImagePickerController.SourceType
}

/// UIKit image picker bridged into SwiftUI. `allowsEditing` provides the native
/// square move-and-scale framing UI for both the photo library and the camera.
struct ContactImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {
        let parent: ContactImagePicker
        init(_ parent: ContactImagePicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // Prefer the user-framed crop; fall back to the original.
            if let img = (info[.editedImage] as? UIImage)
                ?? (info[.originalImage] as? UIImage) {
                parent.onPicked(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Camera capture followed by our own square cropper. UIImagePickerController's
/// built-in camera crop won't let you pan up/down, so we capture the full photo
/// (no editing) and present `SquareCropViewController`, which uses a UIScrollView
/// for unrestricted pan + zoom.
struct CameraCropPicker: UIViewControllerRepresentable {
    /// nil means the user cancelled.
    let onResult: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate,
                             UIImagePickerControllerDelegate {
        let parent: CameraCropPicker
        init(_ parent: CameraCropPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let original = info[.originalImage] as? UIImage else {
                parent.dismiss(); parent.onResult(nil); return
            }
            let cropper = SquareCropViewController(
                image: original.normalizedUp(),
                onCrop: { [parent] cropped in parent.dismiss(); parent.onResult(cropped) },
                onCancel: { [parent] in parent.dismiss(); parent.onResult(nil) })
            cropper.modalPresentationStyle = .fullScreen
            picker.present(cropper, animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss(); parent.onResult(nil)
        }
    }
}

/// A full-screen square cropper backed by a UIScrollView, so the user can pan
/// freely (including up/down) and pinch to zoom — the framing the camera's
/// built-in editor doesn't allow.
final class SquareCropViewController: UIViewController, UIScrollViewDelegate {
    private let image: UIImage
    private let onCrop: (UIImage) -> Void
    private let onCancel: () -> Void

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let maskLayer = CAShapeLayer()
    private var configured = false

    init(image: UIImage,
         onCrop: @escaping (UIImage) -> Void,
         onCancel: @escaping () -> Void) {
        self.image = image
        self.onCrop = onCrop
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        imageView.image = image
        imageView.frame = CGRect(origin: .zero, size: image.size)
        scrollView.addSubview(imageView)
        scrollView.contentSize = image.size

        // Dim everything outside the centered crop square.
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor
        view.layer.addSublayer(maskLayer)

        addControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard scrollView.bounds.width > 0 else { return }

        let side = min(scrollView.bounds.width, scrollView.bounds.height)
        let vInset = (scrollView.bounds.height - side) / 2
        let hInset = (scrollView.bounds.width - side) / 2

        // Update the dimming mask (full screen minus the crop square).
        let cropRect = CGRect(x: hInset, y: vInset, width: side, height: side)
        let path = UIBezierPath(rect: view.bounds)
        path.append(UIBezierPath(rect: cropRect))
        maskLayer.path = path.cgPath
        maskLayer.frame = view.bounds

        guard !configured else { return }
        configured = true

        scrollView.contentInset = UIEdgeInsets(top: vInset, left: hInset,
                                               bottom: vInset, right: hInset)
        let minScale = max(side / image.size.width, side / image.size.height)
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = max(minScale * 4, minScale)
        scrollView.zoomScale = minScale

        // Center the image within the crop square.
        let contentW = image.size.width * minScale
        let contentH = image.size.height * minScale
        scrollView.contentOffset = CGPoint(x: (contentW - side) / 2 - hInset,
                                           y: (contentH - side) / 2 - vInset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    private func addControls() {
        let cancel = UIButton(type: .system)
        cancel.setTitle(tr("Cancel"), for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let use = UIButton(type: .system)
        use.setTitle(tr("Use photo"), for: .normal)
        use.setTitleColor(.white, for: .normal)
        use.titleLabel?.font = .boldSystemFont(ofSize: 17)
        use.addTarget(self, action: #selector(useTapped), for: .touchUpInside)

        for b in [cancel, use] {
            b.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(b)
        }
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            use.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            use.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    @objc private func cancelTapped() { onCancel() }

    @objc private func useTapped() { onCrop(croppedImage()) }

    private func croppedImage() -> UIImage {
        let side = min(scrollView.bounds.width, scrollView.bounds.height)
        let zoom = scrollView.zoomScale
        let offset = scrollView.contentOffset
        let inset = scrollView.contentInset
        // Map the on-screen crop square back into image pixels. `image` is
        // orientation-normalized at scale 1, so points == pixels.
        var rect = CGRect(x: (offset.x + inset.left) / zoom,
                          y: (offset.y + inset.top) / zoom,
                          width: side / zoom,
                          height: side / zoom)
        // Keep the square inside the image (a mid-bounce tap could overshoot).
        rect.origin.x = min(max(0, rect.origin.x), max(0, image.size.width - rect.width))
        rect.origin.y = min(max(0, rect.origin.y), max(0, image.size.height - rect.height))
        rect = rect.integral
        guard let cg = image.cgImage?.cropping(to: rect) else { return image }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }
}

extension UIImage {
    /// Redraw the image upright at scale 1, so crop math in image points maps
    /// directly to pixels (camera photos carry orientation metadata otherwise).
    func normalizedUp() -> UIImage {
        if imageOrientation == .up && scale == 1 { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension ContactAvatar {
    /// Downscale a user-framed image to a small square JPEG. The picker already
    /// returns a square crop, so we scale-to-fill (preserving their framing)
    /// rather than cropping again.
    static func thumbnail(from image: UIImage, max: CGFloat = 240) -> Data? {
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2,
                          y: (image.size.height - side) / 2,
                          width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let target = CGSize(width: max, height: max)
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let out = renderer.image { _ in
            if let cg = image.cgImage?.cropping(to: crop) {
                UIImage(cgImage: cg, scale: image.scale,
                        orientation: image.imageOrientation)
                    .draw(in: CGRect(origin: .zero, size: target))
            } else {
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        return out.jpegData(compressionQuality: 0.8)
    }

    /// Downscale to a small square JPEG so it's cheap to store in app state.
    static func thumbnail(from data: Data, max: CGFloat = 240) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let side = min(img.size.width, img.size.height)
        let crop = CGRect(x: (img.size.width - side) / 2,
                          y: (img.size.height - side) / 2,
                          width: side, height: side)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let target = CGSize(width: max, height: max)
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let out = renderer.image { _ in
            if let cg = img.cgImage?.cropping(to: crop) {
                UIImage(cgImage: cg, scale: img.scale, orientation: img.imageOrientation)
                    .draw(in: CGRect(origin: .zero, size: target))
            } else {
                img.draw(in: CGRect(origin: .zero, size: target))
            }
        }
        return out.jpegData(compressionQuality: 0.7)
    }
}

/// A square, tappable contact tile used across the contact grids.
struct ContactSquare<Destination: View>: View {
    let avatar: ContactAvatar?
    let name: String
    var subtitle: String? = nil
    var badge: (text: String, color: Color)? = nil
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink { destination() } label: {
            VStack(spacing: 8) {
                ContactAvatarView(avatar: avatar, size: 54)
                Text(name).font(.subheadline.weight(.medium))
                    .lineLimit(1).foregroundStyle(Ink.ink)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let badge {
                    Text(badge.text).font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(badge.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(badge.color)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 134)
            .padding(8)
            .background(Ink.ink.opacity(0.04))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.rule, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

let contactGridCols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

// MARK: - Settings editor

struct ContactsOverrideEditor: View {
    @EnvironmentObject var model: AppModel
    @State private var invites: [ContactsRelay.IncomingInvite] = []
    @State private var showTutorialAddContact = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if model.tutorial == .addContact && model.tutorialScreen == "contacts" {
                    Button { showTutorialAddContact = true } label: {
                        Label(tr("Add a contact"),
                              systemImage: "person.crop.circle.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Ink.ink.opacity(0.04))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .stroke(Ink.rule, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .tutorialHighlight(true)
                }
                overrideCard
                if !invites.isEmpty { invitesCard }
                LazyVGrid(columns: gridCols, spacing: 14) {
                    NavigationLink { MyInfoView() } label: {
                        GridCard(symbol: "person.text.rectangle", title: tr("My info"),
                                 subtitle: ContactsRelay.myName.isEmpty
                                    ? ContactsRelay.myCode : ContactsRelay.myName)
                    }
                    NavigationLink { ContactsHubView() } label: {
                        GridCard(symbol: "person.2", title: tr("Contacts"),
                                 subtitle: tr("approvers, blocked"))
                    }
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Trusted contacts"))
        .onAppear { if model.inTutorial { model.tutorialScreen = "contacts" } }
        .task {
            await ContactsRelay.registerSelfIfNeeded()
            invites = (try? await ContactsRelay.incomingInvites()) ?? []
            model.incomingInviteCount = invites.count
        }
        .refreshable {
            invites = (try? await ContactsRelay.incomingInvites()) ?? []
            model.incomingInviteCount = invites.count
        }
        .sheet(isPresented: $showTutorialAddContact) {
            AddContactView(onAdd: { model.addTutorialContact($0) }, tutorialMode: true)
        }
    }

    private var overrideCard: some View {
        let enabled = model.state.overrides.contactsEnabled
        let action = ChangeAction.setContactsOverride(enabled: !enabled)
        let (dir, delay) = model.preview(action)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Trusted-contact override")).font(.headline)
                Spacer()
                Text(enabled ? tr("On") : tr("Off"))
                    .foregroundStyle(enabled ? Ink.accent : Ink.faint)
            }
            Button(enabled ? tr("Queue: turn off") : tr("Queue: turn on")) {
                model.queue(action)
            }
            .buttonStyle(.bordered).controlSize(.small)
            Label(String(format: tr("%@ — takes effect in %@"),
                         dir.label, delay.shortDelayLabel), systemImage: "clock")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.ink.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var invitesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Contact requests")).font(.headline)
            ForEach(invites) { invite in
                VStack(alignment: .leading, spacing: 6) {
                    Text(invite.fromName.isEmpty
                         ? String(format: tr("A Demora user (code %@) wants to add you as their trusted contact."), invite.fromCode)
                         : String(format: tr("%@ (code %@) wants to add you as their trusted contact."), invite.fromName, invite.fromCode))
                        .font(.subheadline)
                    HStack {
                        Button(tr("Accept")) { respond(invite, accept: true) }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button(tr("Decline"), role: .destructive) {
                            respond(invite, accept: false)
                        }.buttonStyle(.bordered).controlSize(.small)
                        Button(tr("Block"), role: .destructive) {
                            ContactsRelay.block(invite.fromCode)
                            respond(invite, accept: false)
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.ink.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ink.rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func respond(_ invite: ContactsRelay.IncomingInvite, accept: Bool) {
        invites.removeAll { $0.id == invite.id }
        model.incomingInviteCount = invites.count
        Task {
            try? await ContactsRelay.respondToInvite(invite, accept: accept)
            invites = (try? await ContactsRelay.incomingInvites()) ?? []
            model.incomingInviteCount = invites.count
        }
    }
}

// MARK: - Contacts hub (approvers, the people you approve for, blocked)

struct ContactsHubView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridCols, spacing: 14) {
                NavigationLink { ContactsDetailView() } label: {
                    GridCard(symbol: "person.crop.circle.badge.plus",
                             title: tr("People who approve for you"),
                             subtitle: String(format: tr("%d total"),
                                              model.state.overrides.contacts.count))
                }
                NavigationLink { ApproveForView() } label: {
                    GridCard(symbol: "checkmark.seal",
                             title: tr("People you approve for"),
                             subtitle: tr("view"))
                }
                NavigationLink { BlockedUsersView() } label: {
                    GridCard(symbol: "hand.raised", title: tr("Blocked users"),
                             subtitle: String(format: tr("%d total"),
                                              ContactsRelay.blockedCodes().count))
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Contacts"))
    }
}

// MARK: - My info

struct MyInfoView: View {
    @State private var myName = ""

    var body: some View {
        Form {
            Section {
                TextField(tr("Your name (optional)"), text: $myName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: myName) { newValue in ContactsRelay.myName = newValue }
            } header: {
                Text(tr("Your name"))
            } footer: {
                Text(tr("Shown to people you ask to approve, so they know it's you."))
            }
            Section {
                HStack {
                    Text(tr("My code"))
                    Spacer()
                    Text(ContactsRelay.myCode)
                        .font(.body.monospaced().bold()).textSelection(.enabled)
                }
            } footer: {
                Text(tr("Share this code so another Demora user can add you. You get a request to accept before it's active."))
            }
        }
        .paper()
        .casedNavigationTitle(tr("My info"))
        .onAppear { myName = ContactsRelay.myName }
    }
}

// MARK: - Contacts detail (contacts + outgoing request history)

struct ContactsDetailView: View {
    @EnvironmentObject var model: AppModel
    @State private var showAdd = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.state.overrides.contacts.isEmpty {
                    Text(tr("No contacts yet")).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: contactGridCols, spacing: 12) {
                        ForEach(model.state.overrides.contacts) { contact in
                            ContactSquare(
                                avatar: avatarFor(contact),
                                name: nameFor(contact),
                                badge: badgeFor(contact)
                            ) {
                                if contact.isEmail {
                                    EmailContactProfileView(contactID: contact.id)
                                } else {
                                    ContactProfileView(contactID: contact.id)
                                }
                            }
                        }
                    }
                }
                Button { showAdd = true } label: {
                    Label(tr("Add contact…"), systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
                NavigationLink { SentHistoryView() } label: {
                    Label(tr("Request history"), systemImage: "clock.arrow.circlepath")
                }
                Text(tr("Both email and Demora-user contacts must confirm before they can approve: email contacts enter a code you email them, Demora users accept in their app. Adding a contact is a less-strict change; removing one is stricter — both go through delays."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("People who approve for you"))
        .sheet(isPresented: $showAdd) { AddContactView() }
    }

    // Demora-user contacts share their name/avatar with the "people you approve
    // for" list; email contacts keep their own.
    private func nameFor(_ c: TrustedContact) -> String {
        if let code = c.latchUserCode {
            return resolvedName(forCode: code, model: model, fallback: tr("Unnamed"))
        }
        return c.name.isEmpty ? tr("Unnamed") : c.name
    }
    private func avatarFor(_ c: TrustedContact) -> ContactAvatar? {
        if let code = c.latchUserCode { return resolvedAvatar(forCode: code, model: model) }
        return c.avatar
    }
    private func badgeFor(_ c: TrustedContact) -> (text: String, color: Color) {
        if c.isPending { return (tr("Pending"), .orange) }
        if let code = c.latchUserCode, model.unavailableContactCodes.contains(code) {
            return (tr("Unavailable"), .gray)
        }
        return (tr("Active"), .green)
    }
}

/// Optional out-of-band verification for a Demora-user contact: a safety code
/// derived from both devices' keys. If it matches on both phones, no one
/// substituted a key in the public database. Client-only; comparing is manual.
struct ContactVerificationSection: View {
    let code: String
    @State private var bump = 0

    var body: some View {
        let fingerprint = ContactCrypto.verificationCode(forCode: code)
        let verified = fingerprint != nil
            && ContactsRelay.verifiedFingerprint(forCode: code) == fingerprint
        Section {
            if let fingerprint {
                HStack {
                    Text(tr("Safety code"))
                    Spacer()
                    Text(fingerprint).font(.body.monospaced())
                        .foregroundStyle(.secondary).textSelection(.enabled)
                }
                if verified {
                    Label(tr("Verified"), systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                } else {
                    Button(tr("Mark as verified")) {
                        ContactsRelay.setVerifiedFingerprint(fingerprint, forCode: code)
                        bump += 1
                    }
                }
            } else {
                Text(tr("Available once you've both added each other."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("Security"))
        } footer: {
            Text(tr("Compare this code with your contact in person or on a call. If it matches on both phones, no one has tampered with the connection."))
        }
    }
}

// MARK: - Contact profile (a person who approves for you)

struct ContactProfileView: View {
    @EnvironmentObject var model: AppModel
    let contactID: UUID
    @State private var name = ""
    @State private var avatar = ContactAvatar()

    private var contact: TrustedContact? {
        model.state.overrides.contacts.first { $0.id == contactID }
    }
    private var navTitle: String {
        let n: String
        if let code = contact?.latchUserCode {
            n = resolvedName(forCode: code, model: model, fallback: contact?.name ?? "")
        } else {
            n = contact?.name ?? ""
        }
        return n.isEmpty ? tr("Contact") : n
    }

    var body: some View {
        Form {
            AvatarEditorView(avatar: $avatar)
                .onChange(of: avatar) {
                    model.setContactAvatar(id: contactID, $0)
                    if let code = contact?.latchUserCode {
                        ContactsRelay.setAvatar($0, forCode: code)
                    }
                }
            Section {
                TextField(tr("Name (optional)"), text: $name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { newValue in
                        model.renameContact(id: contactID, to: newValue)
                        if let code = contact?.latchUserCode {
                            ContactsRelay.setName(newValue, forCode: code)
                        }
                    }
            } header: {
                Text(tr("Name"))
            }
            if let code = contact?.latchUserCode {
                Section {
                    HStack {
                        Text(tr("Code"))
                        Spacer()
                        Text(code).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if contact?.isPending == true {
                        Text(tr("Waiting for them to accept in their Demora app."))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if model.unavailableContactCodes.contains(code) {
                        Label(tr("Can't reach this contact right now — they may have removed Demora or signed out. They won't be able to approve until they're back."),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                } header: {
                    Text(tr("Demora code"))
                }
                ContactVerificationSection(code: code)
            }
            Section {
                Button(tr("Remove…"), role: .destructive) {
                    model.queue(.removeContact(id: contactID))
                }
            }
        }
        .paper()
        .casedNavigationTitle(navTitle)
        .onAppear {
            // Prefer the shared per-code values so a name/photo set from the
            // "people you approve for" side shows here too.
            if let code = contact?.latchUserCode {
                name = resolvedName(forCode: code, model: model, fallback: contact?.name ?? "")
                avatar = resolvedAvatar(forCode: code, model: model)
                    ?? contact?.avatar ?? ContactAvatar()
            } else {
                name = contact?.name ?? ""
                avatar = contact?.avatar ?? ContactAvatar()
            }
        }
    }
}

// MARK: - Email contact profile (confirm by emailed code)

struct EmailContactProfileView: View {
    @EnvironmentObject var model: AppModel
    let contactID: UUID
    @State private var name = ""
    @State private var avatar = ContactAvatar()
    @State private var codeInput = ""
    @State private var sending = false
    @State private var verifying = false
    @State private var sentNow = false
    @State private var error: String?
    @State private var info: String?

    private var contact: TrustedContact? {
        model.state.overrides.contacts.first { $0.id == contactID }
    }
    private var email: String {
        if case .email(let a)? = contact?.kind { return a }
        return ""
    }
    private var inviteSent: Bool {
        guard let id = contact?.inviteId else { return false }
        return sentNow || ContactsRelay.wasSentEmail("invite-" + id)
    }
    private var navTitle: String {
        let n = contact?.name ?? ""
        return n.isEmpty ? tr("Contact") : n
    }

    var body: some View {
        Form {
            AvatarEditorView(avatar: $avatar)
                .onChange(of: avatar) { model.setContactAvatar(id: contactID, $0) }
            Section {
                TextField(tr("Name (optional)"), text: $name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { newValue in
                        model.renameContact(id: contactID, to: newValue)
                    }
            } header: {
                Text(tr("Name"))
            }
            Section {
                HStack {
                    Text(tr("Email"))
                    Spacer()
                    Text(email).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            if contact?.accepted == true {
                Section {
                    Label(tr("Confirmed"), systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                }
            } else if EmailCodeService.isConfigured {
                Section {
                    Button(sending ? tr("Sending…")
                           : (inviteSent ? tr("Resend code")
                                         : tr("Send confirmation code"))) {
                        Task { await sendCode() }
                    }
                    .disabled(sending)
                    if inviteSent {
                        TextField(tr("6-digit code"), text: $codeInput)
                            .keyboardType(.numberPad)
                            .font(.title2.monospaced())
                            .multilineTextAlignment(.center)
                        Button(verifying ? tr("Checking…") : tr("Confirm contact")) {
                            Task { await confirm() }
                        }
                        .disabled(codeInput.count != 6 || verifying)
                    }
                } header: {
                    Text(tr("Confirm by email"))
                } footer: {
                    Text(tr("We email a code to this address. Your contact gives you the code, you enter it here, and then they can approve for you. Until then they can't."))
                }
            } else {
                Section {
                    Text(tr("Email contacts aren't available yet in this build."))
                        .foregroundStyle(.secondary)
                }
            }
            if let info {
                Section { Text(info).font(.footnote).foregroundStyle(.secondary) }
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Button(tr("Remove…"), role: .destructive) {
                    model.queue(.removeContact(id: contactID))
                }
            }
        }
        .paper()
        .casedNavigationTitle(navTitle)
        .onAppear {
            name = contact?.name ?? ""
            avatar = contact?.avatar ?? ContactAvatar()
        }
    }

    private func sendCode() async {
        guard let id = contact?.inviteId, !email.isEmpty else { return }
        sending = true
        defer { sending = false }
        error = nil; info = nil
        do {
            try await EmailCodeService.sendInviteCode(
                inviteId: id, email: email, ownerName: ContactsRelay.myName)
            ContactsRelay.markSent(requestId: "invite-" + id, relay: false)
            sentNow = true
            info = tr("Code sent. Ask your contact for it.")
        } catch let EmailCodeError.rateLimited(global) {
            error = global ? tr("Daily email limit reached. Try again later.")
                           : tr("You've sent too many codes today. Try again tomorrow.")
        } catch {
            self.error = tr("Couldn't send the code. Check your connection and try again.")
        }
    }

    private func confirm() async {
        guard let id = contact?.inviteId else { return }
        verifying = true
        defer { verifying = false }
        error = nil
        do {
            if try await EmailCodeService.verifyInvite(inviteId: id, code: codeInput) {
                model.confirmEmailContact(id: contactID)
                ContactsRelay.clearSent("invite-" + id)
            } else {
                error = tr("That code didn't match. Double-check and try again.")
            }
        } catch {
            // Don't call a network failure a wrong code. (self. — inside a
            // catch, `error` is the caught Error, not our @State var.)
            self.error = tr("Couldn't check the code — check your connection and try again.")
        }
    }
}

// MARK: - People you approve for (grants + incoming request history)

struct ApproveForView: View {
    @EnvironmentObject var model: AppModel
    @State private var grants: [ContactsRelay.PermissionGrant] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if grants.isEmpty {
                    Text(tr("Nobody yet")).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: contactGridCols, spacing: 12) {
                        ForEach(grants) { grant in
                            ContactSquare(
                                avatar: resolvedAvatar(forCode: grant.id, model: model),
                                name: resolvedName(
                                    forCode: grant.id, model: model,
                                    fallback: grant.ownerName.isEmpty
                                        ? String(format: tr("Demora %@"), grant.id)
                                        : grant.ownerName),
                                subtitle: grant.id
                            ) {
                                GrantProfileView(grant: grant, onRevoke: { revoke(grant) })
                            }
                        }
                    }
                }
                NavigationLink { RequestHistoryView() } label: {
                    Label(tr("Request history"), systemImage: "clock.arrow.circlepath")
                }
                Text(tr("These people have you as a trusted contact. Tap one to see their details or add them back. Removing yourself tells them and stops their requests."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("People you approve for"))
        .task { grants = (try? await ContactsRelay.grantsToMe()) ?? [] }
        .refreshable { grants = (try? await ContactsRelay.grantsToMe()) ?? [] }
    }

    private func revoke(_ grant: ContactsRelay.PermissionGrant) {
        grants.removeAll { $0.id == grant.id }
        Task {
            try? await ContactsRelay.revokeGrant(ownerCode: grant.id,
                                                 inviteId: grant.inviteId)
        }
    }
}

// MARK: - Grant profile (a person you approve for)

struct GrantProfileView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let grant: ContactsRelay.PermissionGrant
    var onRevoke: () -> Void
    @State private var added = false
    @State private var error: String?
    @State private var name = ""
    @State private var avatar = ContactAvatar()

    private var alreadyContact: Bool {
        model.state.overrides.contacts.contains { $0.latchUserCode == grant.id }
    }
    private var navTitle: String {
        let n = resolvedName(forCode: grant.id, model: model, fallback: grant.ownerName)
        return n.isEmpty ? tr("Contact") : n
    }

    var body: some View {
        Form {
            AvatarEditorView(avatar: $avatar)
                .onChange(of: avatar) { syncContactAvatar($0, forCode: grant.id, model: model) }
            Section {
                TextField(tr("Name (optional)"), text: $name)
                    .textInputAutocapitalization(.words)
                    .onChange(of: name) { newValue in
                        syncContactName(newValue, forCode: grant.id, model: model)
                    }
                HStack {
                    Text(tr("Code"))
                    Spacer()
                    Text(grant.id).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } header: {
                Text(tr("Name"))
            } footer: {
                if !grant.ownerName.isEmpty {
                    Text(String(format: tr("They call themselves “%@”."), grant.ownerName))
                }
            }
            ContactVerificationSection(code: grant.id)
            Section {
                if alreadyContact || added {
                    Label(tr("Added as a trusted contact"), systemImage: "checkmark.seal")
                        .foregroundStyle(.secondary)
                } else {
                    Button(tr("Add as trusted contact")) { addAsContact() }
                }
            } footer: {
                Text(tr("They'll get a request to accept before they can approve for you. Adding a contact goes through a delay."))
            }
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            Section {
                Button(tr("Remove…"), role: .destructive) {
                    onRevoke()
                    dismiss()
                }
            } footer: {
                Text(tr("Removing yourself tells them and stops their requests."))
            }
        }
        .paper()
        .casedNavigationTitle(navTitle)
        .onAppear {
            name = resolvedName(forCode: grant.id, model: model, fallback: "")
            avatar = resolvedAvatar(forCode: grant.id, model: model) ?? ContactAvatar()
        }
    }

    private func addAsContact() {
        guard grant.id != ContactsRelay.myCode else {
            error = tr("That's your own code.")
            return
        }
        let displayName = resolvedName(forCode: grant.id, model: model,
                                       fallback: grant.ownerName)
        var draft = TrustedContact(name: displayName,
                                   kind: .latchUser(code: grant.id),
                                   accepted: false, inviteId: UUID().uuidString)
        draft.avatar = resolvedAvatar(forCode: grant.id, model: model)
        model.queue(.addContact(draft))
        added = true
    }
}

// MARK: - Outgoing request history (who I've asked to add)

struct SentHistoryView: View {
    @State private var entries: [ContactsRelay.SentRecord] = []

    var body: some View {
        Form {
            if entries.isEmpty {
                Text(tr("No requests yet.")).foregroundStyle(.secondary)
            }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(e.name.isEmpty
                             ? String(format: tr("Demora user %@"), e.code) : e.name)
                            .font(.headline)
                        Spacer()
                        statusBadge(e.status)
                    }
                    Text(String(format: tr("code %@"), e.code))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(Date(timeIntervalSince1970: e.lastDate)
                        .formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .paper()
        .casedNavigationTitle(tr("Request history"))
        .onAppear { entries = ContactsRelay.sentRequestHistory() }
    }

    private func statusBadge(_ status: String) -> some View {
        let pair: (String, Color)
        switch status {
        case "accepted": pair = (tr("Accepted"), .green)
        case "denied":   pair = (tr("Denied"), .red)
        default:         pair = (tr("Pending"), .orange)
        }
        return Text(pair.0).font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(pair.1.opacity(0.15), in: Capsule()).foregroundStyle(pair.1)
    }
}

// MARK: - Request history

struct RequestHistoryView: View {
    @State private var entries: [ContactsRelay.RequestRecord] = []
    @State private var blocked: Set<String> = []

    var body: some View {
        Form {
            if entries.isEmpty {
                Text(tr("No requests yet.")).foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.name.isEmpty
                             ? String(format: tr("Demora user %@"), entry.code)
                             : entry.name)
                            .font(.headline)
                        Spacer()
                        if blocked.contains(entry.code) {
                            Text(tr("Blocked")).font(.caption2.bold())
                                .foregroundStyle(.red)
                        }
                    }
                    Text(String(format: tr("code %@"), entry.code))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(actionLabel(entry.lastAction) + " · "
                         + Date(timeIntervalSince1970: entry.lastDate)
                            .formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.secondary)
                    if blocked.contains(entry.code) {
                        Button(tr("Unblock")) {
                            ContactsRelay.unblock(entry.code); refresh()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Button(tr("Block"), role: .destructive) {
                            ContactsRelay.block(entry.code); refresh()
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .paper()
        .casedNavigationTitle(tr("Request history"))
        .onAppear(perform: refresh)
    }

    private func actionLabel(_ a: String) -> String {
        switch a {
        case "accepted": return tr("Accepted")
        case "declined": return tr("Declined")
        default:         return tr("Requested")
        }
    }

    private func refresh() {
        entries = ContactsRelay.requestHistory()
        blocked = Set(ContactsRelay.blockedCodes())
    }
}

// MARK: - Blocked users

struct BlockedUsersView: View {
    @State private var codes: [String] = []
    @State private var names: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if codes.isEmpty {
                    Text(tr("No blocked users.")).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: contactGridCols, spacing: 12) {
                        ForEach(codes, id: \.self) { code in
                            ContactSquare(
                                avatar: ContactsRelay.avatar(forCode: code),
                                name: (names[code]?.isEmpty == false)
                                    ? names[code]!
                                    : String(format: tr("Demora %@"), code),
                                subtitle: code
                            ) {
                                BlockedUserProfileView(
                                    code: code, name: names[code] ?? "",
                                    onUnblock: { ContactsRelay.unblock(code); refresh() })
                            }
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Ink.paper.ignoresSafeArea())
        .casedNavigationTitle(tr("Blocked users"))
        .onAppear(perform: refresh)
    }

    private func refresh() {
        codes = ContactsRelay.blockedCodes()
        var n: [String: String] = [:]
        for e in ContactsRelay.requestHistory() { n[e.code] = e.name }
        names = n
    }
}

// MARK: - Blocked user profile

struct BlockedUserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    let code: String
    let name: String
    var onUnblock: () -> Void
    @State private var avatar = ContactAvatar()

    var body: some View {
        Form {
            AvatarEditorView(avatar: $avatar)
                .onChange(of: avatar) { ContactsRelay.setAvatar($0, forCode: code) }
            Section {
                HStack {
                    Text(tr("Name"))
                    Spacer()
                    Text(name.isEmpty ? tr("—") : name).foregroundStyle(.secondary)
                }
                HStack {
                    Text(tr("Code"))
                    Spacer()
                    Text(code).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            Section {
                Button(tr("Unblock"), role: .destructive) {
                    onUnblock()
                    dismiss()
                }
            }
        }
        .paper()
        .casedNavigationTitle(name.isEmpty ? tr("Blocked user") : name)
        .onAppear { avatar = ContactsRelay.avatar(forCode: code) ?? ContactAvatar() }
    }
}

struct AddContactView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// During onboarding, contacts are part of initial setup and apply
    /// instantly — the caller collects them instead of queueing changes.
    var onAdd: ((TrustedContact) -> Void)? = nil
    /// In the guided tutorial: prefill a sample, skip the relay code check,
    /// and show the "normally this takes a delay" note.
    var tutorialMode = false

    enum ContactType: String, CaseIterable, Identifiable {
        case email, latchUser
        var id: String { rawValue }
        var label: String {
            self == .email ? tr("Email") : tr("Demora user")
        }
    }

    @State private var name = ""
    @State private var type: ContactType = .email
    @State private var email = ""
    @State private var buddyCode = ""
    @State private var checking = false
    @State private var error: String?
    /// Email send limits, shown when adding an email contact (it sends a mail).
    @State private var emailUsage: EmailCodeService.Usage?
    /// Fresh per add, so re-adding a contact requires a new acceptance.
    @State private var inviteId = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Name")) {
                    TextField(tr("e.g. Mom, Alex"), text: $name)
                }
                .disabled(tutorialMode)
                Section {
                    Picker(tr("Type"), selection: $type) {
                        ForEach(ContactType.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch type {
                    case .email:
                        TextField(tr("Email address"), text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    case .latchUser:
                        TextField(tr("Their Demora code"), text: $buddyCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if type == .email && !EmailCodeService.isConfigured {
                            Text(tr("Email contacts aren't available yet in this build."))
                                .foregroundStyle(.red)
                        } else if type == .latchUser {
                            Text(tr("Ask them for the code in their Demora settings. They'll get a request to accept before they can approve for you."))
                        }
                        Text(tr("Email contacts have a daily send limit; Demora-user contacts don't."))
                    }
                }
                .disabled(tutorialMode)
                if type == .email, EmailCodeService.isConfigured, let u = emailUsage {
                    Section(tr("Email limit")) {
                        EmailUsageBars(usage: u)
                    }
                }
                if tutorialMode {
                    Section {
                        Label(tr("Adding a trusted contact normally waits out a delay. In this tutorial it's instant."),
                              systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                if onAdd == nil {
                    Section {
                        let (dir, delay) = model.preview(.addContact(draft))
                        Label(String(format: tr("%@ — takes effect in %@"),
                                     dir.label, delay.shortDelayLabel),
                              systemImage: "clock")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .paper()
            .casedNavigationTitle(tr("Add contact"))
            .onAppear {
                if tutorialMode {
                    type = .latchUser
                    if name.isEmpty { name = "Alex" }
                    if buddyCode.isEmpty { buddyCode = "DEMO12" }
                }
            }
            .task {
                if EmailCodeService.isConfigured {
                    emailUsage = try? await EmailCodeService.usage()
                }
            }
            .toolbar {
                if !tutorialMode {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("Cancel")) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(checking ? tr("Checking…")
                           : (onAdd == nil ? tr("Queue change") : tr("Add"))) {
                        Task { await submit() }
                    }
                    .disabled(!isValid || checking)
                    .tutorialHighlight(tutorialMode)
                }
            }
        }
    }

    private var draft: TrustedContact {
        switch type {
        case .email:
            return TrustedContact(name: name, kind: .email(
                email.trimmingCharacters(in: .whitespaces).lowercased()),
                accepted: false, inviteId: inviteId)
        case .latchUser:
            return TrustedContact(name: name, kind: .latchUser(code:
                buddyCode.trimmingCharacters(in: .whitespaces).uppercased()),
                accepted: false, inviteId: inviteId)
        }
    }

    private var isValid: Bool {
        guard !name.isEmpty else { return false }
        switch type {
        case .email:
            return EmailCodeService.isConfigured && email.contains("@")
        case .latchUser:
            return buddyCode.trimmingCharacters(in: .whitespaces).count == 6
        }
    }

    private func submit() async {
        let dupExists = model.state.overrides.contacts.contains { existing in
            switch (existing.kind, draft.kind) {
            case let (.email(a), .email(b)): return a == b
            case let (.latchUser(a), .latchUser(b)): return a == b
            default: return false
            }
        }
        if dupExists {
            error = tr("You already have this person as a contact.")
            return
        }
        if case .latchUser(let code) = draft.kind {
            guard code != ContactsRelay.myCode else {
                error = tr("That's your own code — add someone else.")
                return
            }
            if !tutorialMode {
                checking = true
                defer { checking = false }
                let exists = (try? await ContactsRelay.codeExists(code)) ?? false
                guard exists else {
                    error = tr("No Demora user found with that code.")
                    return
                }
            }
        }
        if let onAdd {
            onAdd(draft)
        } else {
            model.queue(.addContact(draft))
        }
        dismiss()
    }
}

// MARK: - Email quota bars

/// The three email-send limits — your personal daily cap, plus the shared
/// daily and monthly pools — drawn as small bars. Shown anywhere an email is
/// about to be sent (asking a contact to approve, or adding an email contact).
struct EmailUsageBars: View {
    let usage: EmailCodeService.Usage

    private func pct(_ a: Int, _ b: Int) -> Int {
        b > 0 ? Int((Double(a) / Double(b) * 100).rounded()) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            bar(tr("You've sent today"),
                fraction: Double(usage.today) / Double(max(1, usage.perDayMax)),
                value: "\(usage.today) / \(usage.perDayMax)")
            bar(tr("All users · today"),
                fraction: Double(usage.dailyTotal) / Double(max(1, usage.dailyMax)),
                value: "\(pct(usage.dailyTotal, usage.dailyMax))%")
            bar(tr("All users · this month"),
                fraction: Double(usage.monthlyTotal) / Double(max(1, usage.monthlyMax)),
                value: "\(pct(usage.monthlyTotal, usage.monthlyMax))%")
        }
        .padding(.vertical, 4)
    }

    private func bar(_ label: String, fraction: Double, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(Ink.accent)
                        .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Override gate ("ask a contact")

struct ContactGateView: View {
    let changes: [PendingChange]
    /// Show the requested-change list at the top. On when opened standalone
    /// (from Home); off inside OverrideGateView, which already shows it.
    var showChangeList: Bool = false
    let onSuccess: () -> Void

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    /// One request id covers the whole group (the first change's id).
    private var reqId: String { changes.first?.id.uuidString ?? "" }

    /// What the contact is asked to approve — every change, not just the first.
    private var combinedSummary: String {
        changes.count == 1
            ? (changes.first?.summary ?? "")
            : String(format: tr("%d changes: %@"), changes.count,
                     changes.map(\.summary).joined(separator: " • "))
    }

    @State private var selected: Set<UUID> = []
    @State private var message = ""
    @State private var sent = false
    @State private var sending = false
    @State private var codeInput = ""
    @State private var verifying = false
    @State private var error: String?
    @State private var pollTask: Task<Void, Never>?

    @State private var emailSent = false
    @State private var latchSent = false
    @State private var deniedDetected = false
    @State private var usage: EmailCodeService.Usage?

    private var contacts: [TrustedContact] { model.state.overrides.contacts }
    private var selectedContacts: [TrustedContact] {
        contacts.filter { selected.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if showChangeList {
                    Section {
                        ForEach(changes) { c in
                            Text(c.summary).font(.subheadline)
                        }
                    } header: {
                        Text(changes.count == 1 ? tr("Requested change")
                                                : tr("Requested changes"))
                    }
                }
                if !sent {
                    Section {
                        ForEach(contacts) { contact in
                            let unusable = contact.isPending
                                || (contact.isEmail && !EmailCodeService.isConfigured)
                            Button {
                                if selected.contains(contact.id) {
                                    selected.remove(contact.id)
                                } else {
                                    selected.insert(contact.id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(contact.name)
                                        Text(contact.isPending
                                             ? tr("Pending — hasn't accepted yet")
                                             : contact.detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if !unusable {
                                        Image(systemName: selected.contains(contact.id)
                                              ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .tint(.primary)
                            .disabled(unusable)
                        }
                    } header: {
                        Text(tr("Who should approve?"))
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tr("Any one approval unlocks the change."))
                            Text(tr("Email contacts have a daily send limit; Demora-user contacts don't."))
                        }
                    }
                    Section {
                        TextField(tr("e.g. why you need this"),
                                  text: $message, axis: .vertical)
                            .lineLimit(2...4)
                    } header: {
                        Text(tr("Message (optional)"))
                    } footer: {
                        Text(tr("Sent along with the request so they know why you're asking."))
                    }
                    Section {
                        Button(sending ? tr("Sending…") : tr("Send request")) {
                            Task { await send() }
                        }
                        .disabled(selected.isEmpty || sending)
                        if let u = usage, contacts.contains(where: \.isEmail) {
                            EmailUsageBars(usage: u)
                        }
                    }
                } else {
                    if emailSent {
                        Section {
                            TextField(tr("6-digit code"), text: $codeInput)
                                .keyboardType(.numberPad)
                                .font(.title2.monospaced())
                                .multilineTextAlignment(.center)
                            Button(verifying ? tr("Checking…") : tr("Verify code")) {
                                Task { await verifyCode() }
                            }
                            .disabled(codeInput.count != 6 || verifying)
                        } header: {
                            Text(tr("Email code"))
                        } footer: {
                            Text(tr("Your contact received a code by email. Enter it here. It expires in 15 minutes."))
                        }
                    }
                    if latchSent {
                        Section {
                            if deniedDetected {
                                Label(tr("Your request was denied."),
                                      systemImage: "hand.raised")
                                    .foregroundStyle(.red)
                            } else {
                                HStack {
                                    ProgressView()
                                    Text(tr("Waiting for approval from their Demora app…"))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } footer: {
                            if !deniedDetected {
                                Text(tr("Checks automatically every few seconds. The request expires after 1 hour."))
                            }
                        }
                    }
                    Section {
                        Button(tr("Send a new request…")) {
                            Task { await startOver() }
                        }
                    } footer: {
                        Text(tr("Cancels this request and lets you pick contacts again."))
                    }
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .paper()
            .casedNavigationTitle(tr("Ask a contact"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close")) { dismiss() }
                }
            }
            .onAppear {
                selected = Set(contacts.filter {
                    $0.isUsable && !($0.isEmail && !EmailCodeService.isConfigured)
                }.map(\.id))
                // Resume a request sent earlier (sheet was closed meanwhile).
                let requestId = reqId
                emailSent = ContactsRelay.wasSentEmail(requestId)
                latchSent = ContactsRelay.wasSentRelay(requestId)
                if emailSent || latchSent { sent = true }
                if latchSent { startPolling(requestId: requestId) }
            }
            .task {
                if EmailCodeService.isConfigured {
                    usage = try? await EmailCodeService.usage()
                }
            }
            .onDisappear { pollTask?.cancel() }
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        error = nil
        let requestId = reqId
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullSummary = trimmed.isEmpty
            ? combinedSummary
            : String(format: tr("%@ — Note: %@"), combinedSummary, trimmed)
        var emailOK = false
        var codesOK = false
        do {
            let emails: [String] = selectedContacts.compactMap {
                if case .email(let address) = $0.kind { return address }
                return nil
            }
            let codes: [String] = selectedContacts.compactMap {
                if case .latchUser(let code) = $0.kind { return code }
                return nil
            }
            if !emails.isEmpty {
                try await EmailCodeService.requestCode(
                    requestId: requestId, emails: emails,
                    summary: fullSummary)
                ContactsRelay.markSent(requestId: requestId, relay: false)
                emailSent = true
                emailOK = true
                usage = try? await EmailCodeService.usage()
            }
            if !codes.isEmpty {
                await ContactsRelay.registerSelfIfNeeded()
                try await ContactsRelay.sendRequests(
                    requestId: requestId, approverCodes: codes,
                    summary: fullSummary)
                ContactsRelay.markSent(requestId: requestId, relay: true)
                latchSent = true
                codesOK = true
                startPolling(requestId: requestId)
            }
        } catch EmailCodeError.rateLimited(let global) {
            self.error = global
                ? tr("Approval emails are at capacity right now. Try again later, or use a Demora contact.")
                : tr("You've used all of today's approval emails. Try again tomorrow.")
            // Refresh so the bars and the upgrade prompt reflect the limit.
            usage = try? await EmailCodeService.usage()
        } catch {
            self.error = tr("Couldn't send the request — check your connection and try again.")
        }
        // Record whatever actually went out — even on a partial failure — so
        // Home's "Awaiting approval" list matches reality.
        if emailOK || codesOK {
            ContactsRelay.recordOutgoing(requestId: requestId,
                                         changeIds: changes.map(\.id),
                                         email: emailOK, relay: codesOK)
            sent = true
        }
    }

    private func verifyCode() async {
        verifying = true
        defer { verifying = false }
        do {
            if try await EmailCodeService.verify(
                requestId: reqId, code: codeInput) {
                await finish()
            } else {
                error = tr("Wrong or expired code.")
                codeInput = ""
            }
        } catch {
            self.error = tr("Couldn't check the code — check your connection and try again.")
        }
    }

    private func startPolling(requestId: String) {
        let since = ContactsRelay.relaySentDate(requestId) ?? .distantPast
        pollTask = Task {
            while !Task.isCancelled {
                if let decisions = try? await ContactsRelay.decisions(
                    requestId: requestId, since: since) {
                    if decisions.approved {
                        await finish()
                        return
                    }
                    if decisions.denied {
                        await MainActor.run { deniedDetected = true }
                        // Keep polling: another chosen contact may approve.
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Abandon the current request (e.g. after a denial) and start fresh.
    @MainActor
    private func startOver() async {
        pollTask?.cancel()
        let requestId = reqId
        ContactsRelay.clearSent(requestId)
        ContactsRelay.clearOutgoing(requestId)
        await ContactsRelay.cleanup(requestId: requestId)
        sent = false
        emailSent = false
        latchSent = false
        deniedDetected = false
        error = nil
        codeInput = ""
    }

    @MainActor
    private func finish() async {
        pollTask?.cancel()
        ContactsRelay.clearSent(reqId)
        ContactsRelay.clearOutgoing(reqId)
        await ContactsRelay.cleanup(requestId: reqId)
        onSuccess()
        dismiss()
    }
}

// MARK: - Approval inbox (shown on Home when someone asks you)
//
// The parent owns loading: a section that renders nothing when empty never
// gets its .task fired, so attaching the fetch here would mean it never runs.

struct ApprovalInboxSection: View {
    let requests: [IncomingRequest]
    let onRespond: (IncomingRequest, Bool) -> Void

    var body: some View {
        if !requests.isEmpty {
            Section {
                ForEach(requests) { request in
                    VStack(alignment: .leading, spacing: 6) {
                        if !request.requesterName.isEmpty {
                            Text(request.requesterName).font(.subheadline.bold())
                        }
                        Text(request.summary).font(.subheadline)
                        Text(request.createdAt.formatted(
                            date: .omitted, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(tr("Approve")) {
                                onRespond(request, true)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Button(tr("Deny"), role: .destructive) {
                                onRespond(request, false)
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(tr("Approval requests"))
            } footer: {
                Text(tr("Someone set you as their trusted contact and wants to skip a waiting period."))
            }
        }
    }
}
