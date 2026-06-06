// Package wabridge is a thin, gomobile-friendly wrapper around the whatsmeow
// WhatsApp multi-device library. It exposes a tiny API surface (all data crosses
// the boundary as JSON strings) so it can be compiled into an iOS xcframework
// with `gomobile bind` and driven from Swift.
package wabridge

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	waCompanionReg "go.mau.fi/whatsmeow/proto/waCompanionReg"
	waProto "go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"

	_ "github.com/mattn/go-sqlite3"
)

// EventHandler is implemented on the Swift side. Every event the bridge wants to
// surface is delivered as a JSON string through HandleEvent.
type EventHandler interface {
	HandleEvent(json string)
}

// event kinds emitted to the host (Swift decodes on "type").
//   qr          {type, code}                 -> render QR for linking
//   pair_success{type, jid, pushName}
//   connected   {type, jid, pushName}
//   logged_out  {type}
//   disconnected{type}
//   chats       {type, chats:[Chat...]}      -> initial list from history sync
//   chat_upsert {type, chat:Chat}            -> live add/update of one chat
//   message     {type, chat:Chat}            -> incoming/outgoing live message
//   contact     {type, jid, name}
//   log         {type, line}

type Chat struct {
	JID         string `json:"jid"`
	Name        string `json:"name"`
	LastMessage string `json:"lastMessage"`
	Timestamp   int64  `json:"timestamp"`
	Unread      int    `json:"unread"`
	Pinned      bool   `json:"pinned"`
	Archived    bool   `json:"archived"`
	Muted       bool   `json:"muted"`
	IsGroup     bool   `json:"isGroup"`
	FromMe      bool   `json:"fromMe"`
}

// Message is a single chat message surfaced to the UI.
type Message struct {
	ID         string `json:"id"`
	ChatJID    string `json:"chatJid"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"timestamp"`
	FromMe     bool   `json:"fromMe"`
	Sender     string `json:"sender"`     // participant JID (groups)
	SenderName string `json:"senderName"` // display name (groups)
	Kind       string `json:"kind"`       // text, image, video, audio, sticker, document, ...
	Caption    string `json:"caption"`    // caption for media messages
	Mimetype   string `json:"mimetype"`   // media MIME type
	Filename   string `json:"filename"`   // document file name
	HasMedia   bool   `json:"hasMedia"`   // true if downloadable media is attached
	MediaPath  string `json:"mediaPath"`  // local file path once downloaded
}

type bridge struct {
	mu        sync.Mutex
	client    *whatsmeow.Client
	handler   EventHandler
	ctx       context.Context
	cancel    context.CancelFunc
	pushNames map[string]string           // jid (user@server) -> push name
	pairCh    chan [2]string              // {method, phone} selected by the UI
	messages  map[string][]Message        // chat jid -> message history
	mediaMsgs map[string]*waProto.Message // message id -> raw message (media only)
	dataDir   string                      // writable app dir (session db + media cache)
}

var (
	gmu sync.Mutex
	b   *bridge
)

func emit(h EventHandler, v interface{}) {
	if h == nil {
		return
	}
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	h.HandleEvent(string(data))
}

func (br *bridge) emit(v interface{}) { emit(br.handler, v) }

// fwdLogger routes whatsmeow's logs into the in-app connection log so failures
// (e.g. a rejected pairing) are visible under Settings → view connection log.
type fwdLogger struct {
	br     *bridge
	module string
}

func (l fwdLogger) out(level, msg string, args ...interface{}) {
	l.br.logln(fmt.Sprintf("[%s/%s] %s", level, l.module, fmt.Sprintf(msg, args...)))
}
func (l fwdLogger) Warnf(msg string, args ...interface{})  { l.out("warn", msg, args...) }
func (l fwdLogger) Errorf(msg string, args ...interface{}) { l.out("error", msg, args...) }
func (l fwdLogger) Infof(msg string, args ...interface{})  { l.out("info", msg, args...) }
func (l fwdLogger) Debugf(msg string, args ...interface{}) {} // omitted: too noisy
func (l fwdLogger) Sub(module string) waLog.Logger {
	return fwdLogger{br: l.br, module: l.module + "." + module}
}

func (br *bridge) logln(line string) {
	br.emit(map[string]interface{}{"type": "log", "line": line})
}

// Start boots the WhatsApp client. dataDir is a writable app directory used to
// store the encrypted session database. It blocks until the context is
// cancelled (call it from a background thread / Task in Swift).
func Start(dataDir string, handler EventHandler) {
	gmu.Lock()
	if b != nil {
		gmu.Unlock()
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	br := &bridge{handler: handler, ctx: ctx, cancel: cancel, pushNames: map[string]string{}, pairCh: make(chan [2]string, 1), messages: map[string][]Message{}, mediaMsgs: map[string]*waProto.Message{}}
	b = br
	gmu.Unlock()

	br.run(dataDir)
}

func (br *bridge) run(dataDir string) {
	br.dataDir = dataDir
	// Present as a normal Chrome web companion. WhatsApp rejects phone-number
	// pairing when the platform is unknown (the whatsmeow default), so set a
	// real browser identity that matches the PairPhone client type below.
	store.DeviceProps.Os = proto("Chrome")
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_CHROME.Enum()

	dbLog := fwdLogger{br: br, module: "db"}
	dsn := fmt.Sprintf("file:%s/session.db?_foreign_keys=on&_pragma=journal_mode(WAL)", dataDir)
	container, err := sqlstore.New(br.ctx, "sqlite3", dsn, dbLog)
	if err != nil {
		br.logln("db error: " + err.Error())
		return
	}
	deviceStore, err := container.GetFirstDevice(br.ctx)
	if err != nil {
		br.logln("device error: " + err.Error())
		return
	}

	clientLog := fwdLogger{br: br, module: "wa"}
	client := whatsmeow.NewClient(deviceStore, clientLog)
	br.client = client
	client.AddEventHandler(br.eventHandler)

	if client.Store.ID == nil {
		// Not logged in yet: ask the UI which method to use.
		br.emit(map[string]interface{}{"type": "need_pairing"})
		var choice [2]string
		select {
		case choice = <-br.pairCh:
		case <-br.ctx.Done():
			return
		}
		method, phone := choice[0], normalizePhone(choice[1])

		// GetQRChannel must be called before Connect for both flows.
		qrChan, _ := client.GetQRChannel(br.ctx)
		if err := client.Connect(); err != nil {
			br.logln("connect error: " + err.Error())
			return
		}

		if method == "phone" {
			// Wait for the first QR event so the socket is fully established,
			// then request a phone pairing code instead of showing a QR.
			<-qrChan
			code, err := client.PairPhone(br.ctx, phone, true, whatsmeow.PairClientChrome, "Chrome (Linux)")
			if err != nil {
				br.logln("pair phone error: " + err.Error())
				br.emit(map[string]interface{}{"type": "pair_error", "error": err.Error()})
			} else {
				br.emit(map[string]interface{}{"type": "pair_code", "code": code})
			}
			// Drain remaining QR events (ignored during code pairing).
			go func() {
				for range qrChan {
				}
			}()
		} else {
			for evt := range qrChan {
				if evt.Event == "code" {
					br.emit(map[string]interface{}{"type": "qr", "code": evt.Code})
				} else {
					br.logln("qr event: " + evt.Event)
				}
			}
		}
	} else {
		if err := client.Connect(); err != nil {
			br.logln("connect error: " + err.Error())
			return
		}
	}

	<-br.ctx.Done()
	client.Disconnect()
}

func (br *bridge) selfName() string {
	if br.client != nil && br.client.Store != nil && br.client.Store.PushName != "" {
		return br.client.Store.PushName
	}
	return ""
}

func (br *bridge) selfJID() string {
	if br.client != nil && br.client.Store != nil && br.client.Store.ID != nil {
		return br.client.Store.ID.User
	}
	return ""
}

func (br *bridge) eventHandler(rawEvt interface{}) {
	switch evt := rawEvt.(type) {
	case *events.Connected:
		br.emit(map[string]interface{}{"type": "connected", "jid": br.selfJID(), "pushName": br.selfName()})
	case *events.PairSuccess:
		br.emit(map[string]interface{}{"type": "pair_success", "jid": evt.ID.User, "pushName": br.selfName()})
	case *events.LoggedOut:
		br.emit(map[string]interface{}{"type": "logged_out"})
	case *events.Disconnected:
		br.emit(map[string]interface{}{"type": "disconnected"})
	case *events.PushName:
		br.mu.Lock()
		br.pushNames[evt.JID.User] = evt.NewPushName
		br.mu.Unlock()
		br.emit(map[string]interface{}{"type": "contact", "jid": evt.JID.String(), "name": evt.NewPushName})
	case *events.Contact:
		name := evt.Action.GetFullName()
		if name == "" {
			name = evt.Action.GetFirstName()
		}
		if name != "" {
			br.mu.Lock()
			br.pushNames[evt.JID.User] = name
			br.mu.Unlock()
			br.emit(map[string]interface{}{"type": "contact", "jid": evt.JID.String(), "name": name})
		}
	case *events.BusinessName:
		if evt.NewBusinessName != "" {
			br.emit(map[string]interface{}{"type": "contact", "jid": evt.JID.String(), "name": evt.NewBusinessName})
		}
	case *events.Pin:
		br.emit(map[string]interface{}{"type": "chat_flags", "jid": evt.JID.String(), "pinned": evt.Action.GetPinned()})
	case *events.Archive:
		br.emit(map[string]interface{}{"type": "chat_flags", "jid": evt.JID.String(), "archived": evt.Action.GetArchived()})
	case *events.Mute:
		br.emit(map[string]interface{}{"type": "chat_flags", "jid": evt.JID.String(), "muted": evt.Action.GetMuted()})
	case *events.HistorySync:
		br.handleHistorySync(evt)
	case *events.Message:
		br.handleMessage(evt)
	}
}

// displayName resolves the best human-readable name for a JID, checking (in
// order) an explicit fallback, the on-device contacts store (address-book name
// → business name → push name), the live push-name cache, and finally the bare
// user id. This is what fixes "no names in the chat list".
func (br *bridge) displayName(jid types.JID, fallbackName string) string {
	if fallbackName != "" {
		return fallbackName
	}
	if br.client != nil && br.client.Store != nil && br.client.Store.Contacts != nil {
		if ci, err := br.client.Store.Contacts.GetContact(br.ctx, jid.ToNonAD()); err == nil && ci.Found {
			switch {
			case ci.FullName != "":
				return ci.FullName
			case ci.FirstName != "":
				return ci.FirstName
			case ci.BusinessName != "":
				return ci.BusinessName
			case ci.PushName != "":
				return ci.PushName
			}
		}
	}
	br.mu.Lock()
	n := br.pushNames[jid.User]
	br.mu.Unlock()
	if n != "" {
		return n
	}
	return jid.User
}

// phoneFor returns a display phone number for a user JID, resolving @lid hidden
// identities back to a real phone number where possible (fixes "wrong number").
func (br *bridge) phoneFor(jid types.JID) string {
	if jid.Server == types.DefaultUserServer {
		return "+" + jid.User
	}
	if jid.Server == types.HiddenUserServer && br.client != nil && br.client.Store != nil {
		if br.client.Store.LIDs != nil {
			if pn, err := br.client.Store.LIDs.GetPNForLID(br.ctx, jid.ToNonAD()); err == nil && pn.User != "" {
				return "+" + pn.User
			}
		}
		if br.client.Store.Contacts != nil {
			if ci, err := br.client.Store.Contacts.GetContact(br.ctx, jid.ToNonAD()); err == nil && ci.RedactedPhone != "" {
				return ci.RedactedPhone
			}
		}
		return ""
	}
	return "+" + jid.User
}

func (br *bridge) handleMessage(evt *events.Message) {
	text := extractText(evt.Message)
	if text == "" {
		text = describeMessage(evt.Message)
	}
	chat := Chat{
		JID:         evt.Info.Chat.String(),
		Name:        br.displayName(evt.Info.Chat, ""),
		LastMessage: text,
		Timestamp:   evt.Info.Timestamp.Unix(),
		FromMe:      evt.Info.IsFromMe,
		IsGroup:     evt.Info.IsGroup,
	}
	if !evt.Info.IsFromMe {
		chat.Unread = 1
	}
	br.emit(map[string]interface{}{"type": "message", "chat": chat})

	msg := Message{
		ID:        evt.Info.ID,
		ChatJID:   evt.Info.Chat.String(),
		Text:      text,
		Timestamp: evt.Info.Timestamp.Unix(),
		FromMe:    evt.Info.IsFromMe,
		Kind:      messageKind(evt.Message),
	}
	if evt.Info.IsGroup {
		msg.Sender = evt.Info.Sender.String()
		msg.SenderName = br.displayName(evt.Info.Sender, evt.Info.PushName)
	}
	br.fillMedia(&msg, evt.Message)
	br.mu.Lock()
	br.messages[msg.ChatJID] = append(br.messages[msg.ChatJID], msg)
	if msg.HasMedia {
		br.mediaMsgs[msg.ID] = evt.Message
	}
	br.mu.Unlock()
	br.emit(map[string]interface{}{"type": "new_message", "message": msg})
}

// fillMedia populates media metadata on a Message (caption, mimetype, filename)
// and marks HasMedia so the UI knows it can request a download.
func (br *bridge) fillMedia(m *Message, raw *waProto.Message) {
	if raw == nil {
		return
	}
	switch {
	case raw.GetImageMessage() != nil:
		im := raw.GetImageMessage()
		m.Caption, m.Mimetype, m.HasMedia = im.GetCaption(), im.GetMimetype(), true
	case raw.GetVideoMessage() != nil:
		vm := raw.GetVideoMessage()
		m.Caption, m.Mimetype, m.HasMedia = vm.GetCaption(), vm.GetMimetype(), true
		if vm.GetGifPlayback() {
			m.Kind = "gif"
		}
	case raw.GetStickerMessage() != nil:
		m.Mimetype, m.HasMedia = raw.GetStickerMessage().GetMimetype(), true
	case raw.GetAudioMessage() != nil:
		am := raw.GetAudioMessage()
		m.Mimetype, m.HasMedia = am.GetMimetype(), true
		if am.GetPTT() {
			m.Kind = "voice"
		}
	case raw.GetDocumentMessage() != nil:
		dm := raw.GetDocumentMessage()
		m.Caption, m.Mimetype, m.Filename, m.HasMedia = dm.GetCaption(), dm.GetMimetype(), dm.GetFileName(), true
	}
}

func (br *bridge) handleHistorySync(evt *events.HistorySync) {
	// Capture push names that ride along with the sync.
	for _, pn := range evt.Data.GetPushnames() {
		if pn.GetID() != "" && pn.GetPushname() != "" {
			jid, err := types.ParseJID(pn.GetID())
			if err == nil {
				br.mu.Lock()
				br.pushNames[jid.User] = pn.GetPushname()
				br.mu.Unlock()
			}
		}
	}

	var chats []Chat
	for _, conv := range evt.Data.GetConversations() {
		jid, err := types.ParseJID(conv.GetID())
		if err != nil {
			continue
		}
		c := Chat{
			JID:      jid.String(),
			Name:     br.displayName(jid, conv.GetName()),
			Unread:   int(conv.GetUnreadCount()),
			Pinned:   conv.GetPinned() != 0,
			Archived: conv.GetArchived(),
			Muted:    conv.GetMuteEndTime() > 0,
			IsGroup:  jid.Server == types.GroupServer,
		}
		// The history-sync conversation flags are often empty; the locally
		// synced chat settings (from WhatsApp app-state) are authoritative for
		// pin/archive/mute, so prefer them when present.
		if br.client != nil && br.client.Store != nil && br.client.Store.ChatSettings != nil {
			if cs, err := br.client.Store.ChatSettings.GetChatSettings(br.ctx, jid); err == nil && cs.Found {
				c.Pinned = cs.Pinned
				c.Archived = cs.Archived
				c.Muted = cs.MutedUntil.After(time.Now())
			}
		}
		if msgs := conv.GetMessages(); len(msgs) > 0 {
			// Store the full (recent) history for this chat, tracking the most
			// recent message so the list preview/ordering use the latest one
			// (history-sync message order is not guaranteed newest-first).
			var stored []Message
			var latest *Message
			for _, hsMsg := range msgs {
				wm := hsMsg.GetMessage()
				if wm == nil {
					continue
				}
				inner := wm.GetMessage()
				text := extractText(inner)
				if text == "" {
					text = describeMessage(inner)
				}
				m := Message{
					ID:        wm.GetKey().GetID(),
					ChatJID:   jid.String(),
					Text:      text,
					Timestamp: int64(wm.GetMessageTimestamp()),
					FromMe:    wm.GetKey().GetFromMe(),
					Kind:      messageKind(inner),
				}
				if c.IsGroup {
					m.Sender = wm.GetKey().GetParticipant()
					m.SenderName = wm.GetPushName()
				}
				br.fillMedia(&m, inner)
				if m.HasMedia && m.ID != "" {
					br.mu.Lock()
					br.mediaMsgs[m.ID] = inner
					br.mu.Unlock()
				}
				stored = append(stored, m)
				if latest == nil || m.Timestamp > latest.Timestamp {
					cp := m
					latest = &cp
				}
			}
			if latest != nil {
				c.Timestamp = latest.Timestamp
				c.FromMe = latest.FromMe
				c.LastMessage = latest.Text
			}
			if len(stored) > 0 {
				br.mu.Lock()
				br.messages[jid.String()] = stored
				br.mu.Unlock()
			}
		}
		chats = append(chats, c)
	}
	if len(chats) > 0 {
		br.emit(map[string]interface{}{"type": "chats", "chats": chats})
	}
}

// Pair selects the linking method after the bridge has emitted "need_pairing".
// method is "qr" or "phone"; phone is the full international number (used only
// when method == "phone", e.g. "491701234567").
func Pair(method, phone string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil {
		return
	}
	select {
	case br.pairCh <- [2]string{method, phone}:
	default:
	}
}

// RequestNewCode asks WhatsApp for a fresh 8-character phone-pairing code on
// the already-connected session. Call this when the user taps "new code".
func RequestNewCode(phone string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	p := normalizePhone(phone)
	br.logln("requesting new pairing code for +" + p)
	code, err := br.client.PairPhone(br.ctx, p, true, whatsmeow.PairClientChrome, "Chrome (Linux)")
	if err != nil {
		br.logln("new code error: " + err.Error())
		br.emit(map[string]interface{}{"type": "pair_error", "error": err.Error()})
	} else {
		br.logln("new pairing code issued")
		br.emit(map[string]interface{}{"type": "pair_code", "code": code})
	}
}

// FetchPicture asynchronously resolves a contact/group profile-picture URL and
// emits a {type:"chat_picture", jid, url} event so the list can show avatars.
func FetchPicture(jidStr string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	go func() {
		jid, err := types.ParseJID(jidStr)
		if err != nil {
			return
		}
		// Resolve a real name for the row while we're here (fixes "no names in
		// the chat list" for contacts that weren't named in the history sync).
		if jid.Server != types.GroupServer {
			if name := br.displayName(jid, ""); name != "" && name != jid.User {
				br.emit(map[string]interface{}{"type": "contact", "jid": jid.String(), "name": name})
			}
		}
		pic, err := br.client.GetProfilePictureInfo(br.ctx, jid, &whatsmeow.GetProfilePictureParams{Preview: true})
		if err != nil || pic == nil || pic.URL == "" {
			return
		}
		br.emit(map[string]interface{}{"type": "chat_picture", "jid": jidStr, "url": pic.URL})
	}()
}

func normalizePhone(s string) string {
	out := make([]rune, 0, len(s))
	for _, r := range s {
		if r >= '0' && r <= '9' {
			out = append(out, r)
		}
	}
	return string(out)
}

// OpenChat emits the stored message history for a chat and asynchronously
// fetches the contact/group profile (name, about/topic, picture URL).
func OpenChat(jidStr string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil {
		return
	}
	br.mu.Lock()
	msgs := append([]Message(nil), br.messages[jidStr]...)
	br.mu.Unlock()
	sort.Slice(msgs, func(i, j int) bool { return msgs[i].Timestamp < msgs[j].Timestamp })
	br.emit(map[string]interface{}{"type": "messages", "jid": jidStr, "messages": msgs})
	go br.fetchProfile(jidStr)
}

func (br *bridge) fetchProfile(jidStr string) {
	if br.client == nil {
		return
	}
	jid, err := types.ParseJID(jidStr)
	if err != nil {
		return
	}
	prof := map[string]interface{}{"type": "profile", "jid": jidStr}
	if jid.Server == types.GroupServer {
		prof["isGroup"] = true
		if gi, err := br.client.GetGroupInfo(br.ctx, jid); err == nil {
			prof["name"] = gi.Name
			prof["about"] = gi.Topic
			prof["participants"] = len(gi.Participants)
		} else {
			prof["name"] = br.displayName(jid, "")
		}
	} else {
		prof["isGroup"] = false
		prof["name"] = br.displayName(jid, "")
		if phone := br.phoneFor(jid); phone != "" {
			prof["phone"] = phone
		}
		about := ""
		if infos, err := br.client.GetUserInfo(br.ctx, []types.JID{jid}); err == nil {
			for _, ui := range infos {
				about = ui.Status
				break
			}
		}
		// Business accounts expose an address we can show when there's no status.
		if about == "" {
			if bp, err := br.client.GetBusinessProfile(br.ctx, jid); err == nil && bp != nil && bp.Address != "" {
				about = bp.Address
			}
		}
		if about != "" {
			prof["about"] = about
		}
	}
	if pic, err := br.client.GetProfilePictureInfo(br.ctx, jid, &whatsmeow.GetProfilePictureParams{Preview: true}); err == nil && pic != nil {
		prof["pictureURL"] = pic.URL
	}
	br.emit(prof)
}

// SendText sends a plain text message to the given JID (e.g. "123@s.whatsapp.net").
func SendText(jidStr, text string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	jid, err := types.ParseJID(jidStr)
	if err != nil {
		return
	}
	msg := &waProto.Message{Conversation: proto(text)}
	ctx, cancel := context.WithTimeout(br.ctx, 30*time.Second)
	defer cancel()
	resp, sendErr := br.client.SendMessage(ctx, jid, msg)

	ts := time.Now().Unix()
	id := ""
	if sendErr == nil {
		ts = resp.Timestamp.Unix()
		id = string(resp.ID)
	} else {
		br.logln("send error: " + sendErr.Error())
	}
	m := Message{ID: id, ChatJID: jidStr, Text: text, Timestamp: ts, FromMe: true, Kind: "text"}
	br.mu.Lock()
	br.messages[jidStr] = append(br.messages[jidStr], m)
	br.mu.Unlock()
	br.emit(map[string]interface{}{"type": "new_message", "message": m})
	br.emit(map[string]interface{}{"type": "message", "chat": Chat{
		JID: jidStr, Name: br.displayName(jid, ""), LastMessage: text,
		Timestamp: ts, FromMe: true, IsGroup: jid.Server == types.GroupServer,
	}})
}

// DownloadMedia decrypts the media attached to a stored message, writes it to
// the local media cache and emits {type:"media", id, path} when it's ready.
func DownloadMedia(id string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	br.mu.Lock()
	raw := br.mediaMsgs[id]
	br.mu.Unlock()
	if raw == nil {
		return
	}
	go func() {
		part, ext := mediaPart(raw)
		if part == nil {
			return
		}
		dir := filepath.Join(br.dataDir, "media")
		_ = os.MkdirAll(dir, 0o700)
		path := filepath.Join(dir, id+ext)
		if _, err := os.Stat(path); err == nil {
			br.emit(map[string]interface{}{"type": "media", "id": id, "path": path})
			return
		}
		data, err := br.client.Download(br.ctx, part)
		if err != nil {
			br.logln("download error: " + err.Error())
			return
		}
		if err := os.WriteFile(path, data, 0o600); err != nil {
			br.logln("media write error: " + err.Error())
			return
		}
		br.emit(map[string]interface{}{"type": "media", "id": id, "path": path})
	}()
}

// SendMedia uploads a local file and sends it to the chat. kind is one of
// "image", "video", "gif", "audio", "voice", "document".
func SendMedia(jidStr, path, kind, caption string) {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	jid, err := types.ParseJID(jidStr)
	if err != nil {
		return
	}
	go func() {
		data, err := os.ReadFile(path)
		if err != nil {
			br.logln("read media error: " + err.Error())
			return
		}
		mime := http.DetectContentType(data)
		ctx, cancel := context.WithTimeout(br.ctx, 120*time.Second)
		defer cancel()
		up, err := br.client.Upload(ctx, data, uploadTypeForKind(kind, mime))
		if err != nil {
			br.logln("upload error: " + err.Error())
			return
		}
		msg := buildMediaMessage(kind, mime, caption, filepath.Base(path), up)
		if msg == nil {
			return
		}
		resp, err := br.client.SendMessage(ctx, jid, msg)
		ts := time.Now().Unix()
		id := ""
		if err != nil {
			br.logln("send media error: " + err.Error())
		} else {
			ts = resp.Timestamp.Unix()
			id = string(resp.ID)
		}
		m := Message{ID: id, ChatJID: jidStr, Timestamp: ts, FromMe: true, Kind: kind, Caption: caption, Mimetype: mime, HasMedia: true}
		if id != "" {
			dir := filepath.Join(br.dataDir, "media")
			_ = os.MkdirAll(dir, 0o700)
			dst := filepath.Join(dir, id+extFromMime(mime, ".bin"))
			_ = os.WriteFile(dst, data, 0o600)
			m.MediaPath = dst
			br.mu.Lock()
			br.mediaMsgs[id] = msg
			br.mu.Unlock()
		}
		br.mu.Lock()
		br.messages[jidStr] = append(br.messages[jidStr], m)
		br.mu.Unlock()
		br.emit(map[string]interface{}{"type": "new_message", "message": m})
		br.emit(map[string]interface{}{"type": "message", "chat": Chat{
			JID: jidStr, Name: br.displayName(jid, ""), LastMessage: describeMessage(msg),
			Timestamp: ts, FromMe: true, IsGroup: jid.Server == types.GroupServer,
		}})
	}()
}

func mediaPart(m *waProto.Message) (whatsmeow.DownloadableMessage, string) {
	switch {
	case m.GetImageMessage() != nil:
		return m.GetImageMessage(), extFromMime(m.GetImageMessage().GetMimetype(), ".jpg")
	case m.GetVideoMessage() != nil:
		return m.GetVideoMessage(), extFromMime(m.GetVideoMessage().GetMimetype(), ".mp4")
	case m.GetStickerMessage() != nil:
		return m.GetStickerMessage(), ".webp"
	case m.GetAudioMessage() != nil:
		return m.GetAudioMessage(), extFromMime(m.GetAudioMessage().GetMimetype(), ".ogg")
	case m.GetDocumentMessage() != nil:
		return m.GetDocumentMessage(), docExt(m.GetDocumentMessage())
	}
	return nil, ""
}

func extFromMime(mime, def string) string {
	mime = strings.TrimSpace(strings.SplitN(mime, ";", 2)[0])
	switch mime {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/gif":
		return ".gif"
	case "image/webp":
		return ".webp"
	case "video/mp4":
		return ".mp4"
	case "audio/ogg":
		return ".ogg"
	case "audio/mpeg":
		return ".mp3"
	case "audio/mp4", "audio/aac":
		return ".m4a"
	}
	if i := strings.LastIndex(mime, "/"); i >= 0 && i < len(mime)-1 {
		return "." + mime[i+1:]
	}
	return def
}

func docExt(dm *waProto.DocumentMessage) string {
	if fn := dm.GetFileName(); fn != "" {
		if e := filepath.Ext(fn); e != "" {
			return e
		}
	}
	return extFromMime(dm.GetMimetype(), ".bin")
}

func uploadTypeForKind(kind, mime string) whatsmeow.MediaType {
	switch kind {
	case "image", "sticker":
		return whatsmeow.MediaImage
	case "video", "gif":
		return whatsmeow.MediaVideo
	case "audio", "voice":
		return whatsmeow.MediaAudio
	}
	switch {
	case strings.HasPrefix(mime, "image/"):
		return whatsmeow.MediaImage
	case strings.HasPrefix(mime, "video/"):
		return whatsmeow.MediaVideo
	case strings.HasPrefix(mime, "audio/"):
		return whatsmeow.MediaAudio
	}
	return whatsmeow.MediaDocument
}

func buildMediaMessage(kind, mime, caption, filename string, up whatsmeow.UploadResponse) *waProto.Message {
	var capPtr *string
	if caption != "" {
		capPtr = proto(caption)
	}
	switch kind {
	case "image":
		return &waProto.Message{ImageMessage: &waProto.ImageMessage{
			URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey,
			Mimetype: proto(mime), Caption: capPtr,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength,
		}}
	case "video", "gif":
		vm := &waProto.VideoMessage{
			URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey,
			Mimetype: proto(mime), Caption: capPtr,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength,
		}
		if kind == "gif" {
			t := true
			vm.GifPlayback = &t
		}
		return &waProto.Message{VideoMessage: vm}
	case "audio", "voice":
		am := &waProto.AudioMessage{
			URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey,
			Mimetype:      proto(mime),
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength,
		}
		if kind == "voice" {
			t := true
			am.PTT = &t
		}
		return &waProto.Message{AudioMessage: am}
	}
	return &waProto.Message{DocumentMessage: &waProto.DocumentMessage{
		URL: &up.URL, DirectPath: &up.DirectPath, MediaKey: up.MediaKey,
		Mimetype: proto(mime), FileName: proto(filename), Caption: capPtr,
		FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: &up.FileLength,
	}}
}

// Logout unlinks the device and clears the local session.
func Logout() {
	gmu.Lock()
	br := b
	gmu.Unlock()
	if br == nil || br.client == nil {
		return
	}
	_ = br.client.Logout(br.ctx)
}

// Stop disconnects and tears down the bridge.
func Stop() {
	gmu.Lock()
	br := b
	b = nil
	gmu.Unlock()
	if br != nil && br.cancel != nil {
		br.cancel()
	}
}

func proto(s string) *string { return &s }

func messageKind(m *waProto.Message) string {
	if m == nil {
		return "text"
	}
	switch {
	case m.GetImageMessage() != nil:
		return "image"
	case m.GetVideoMessage() != nil:
		return "video"
	case m.GetAudioMessage() != nil:
		return "audio"
	case m.GetDocumentMessage() != nil:
		return "document"
	case m.GetStickerMessage() != nil:
		return "sticker"
	case m.GetContactMessage() != nil:
		return "contact"
	case m.GetLocationMessage() != nil:
		return "location"
	}
	return "text"
}

func extractText(m *waProto.Message) string {
	if m == nil {
		return ""
	}
	if m.GetConversation() != "" {
		return m.GetConversation()
	}
	if ext := m.GetExtendedTextMessage(); ext != nil {
		return ext.GetText()
	}
	return ""
}

func describeMessage(m *waProto.Message) string {
	if m == nil {
		return ""
	}
	switch {
	case m.GetImageMessage() != nil:
		if cap := m.GetImageMessage().GetCaption(); cap != "" {
			return "📷 " + cap
		}
		return "📷 Photo"
	case m.GetVideoMessage() != nil:
		return "🎥 Video"
	case m.GetAudioMessage() != nil:
		return "🎤 Audio"
	case m.GetDocumentMessage() != nil:
		return "📎 Document"
	case m.GetStickerMessage() != nil:
		return "🌟 Sticker"
	case m.GetContactMessage() != nil:
		return "👤 Contact"
	case m.GetLocationMessage() != nil:
		return "📍 Location"
	}
	return ""
}
