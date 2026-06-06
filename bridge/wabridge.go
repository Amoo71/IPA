// Package wabridge is a thin, gomobile-friendly wrapper around the whatsmeow
// WhatsApp multi-device library. It exposes a tiny API surface (all data crosses
// the boundary as JSON strings) so it can be compiled into an iOS xcframework
// with `gomobile bind` and driven from Swift.
package wabridge

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	waProto "go.mau.fi/whatsmeow/proto/waE2E"
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

type bridge struct {
	mu        sync.Mutex
	client    *whatsmeow.Client
	handler   EventHandler
	ctx       context.Context
	cancel    context.CancelFunc
	pushNames map[string]string // jid (user@server) -> push name
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
	br := &bridge{handler: handler, ctx: ctx, cancel: cancel, pushNames: map[string]string{}}
	b = br
	gmu.Unlock()

	br.run(dataDir)
}

func (br *bridge) run(dataDir string) {
	dbLog := waLog.Stdout("DB", "WARN", true)
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

	clientLog := waLog.Stdout("Client", "INFO", true)
	client := whatsmeow.NewClient(deviceStore, clientLog)
	br.client = client
	client.AddEventHandler(br.eventHandler)

	if client.Store.ID == nil {
		// Not logged in: request a QR code for linking.
		qrChan, _ := client.GetQRChannel(br.ctx)
		if err := client.Connect(); err != nil {
			br.logln("connect error: " + err.Error())
			return
		}
		for evt := range qrChan {
			if evt.Event == "code" {
				br.emit(map[string]interface{}{"type": "qr", "code": evt.Code})
			} else {
				br.logln("qr event: " + evt.Event)
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
		if name != "" {
			br.mu.Lock()
			br.pushNames[evt.JID.User] = name
			br.mu.Unlock()
			br.emit(map[string]interface{}{"type": "contact", "jid": evt.JID.String(), "name": name})
		}
	case *events.HistorySync:
		br.handleHistorySync(evt)
	case *events.Message:
		br.handleMessage(evt)
	}
}

func (br *bridge) displayName(jid types.JID, fallbackName string) string {
	if fallbackName != "" {
		return fallbackName
	}
	br.mu.Lock()
	n := br.pushNames[jid.User]
	br.mu.Unlock()
	if n != "" {
		return n
	}
	return jid.User
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
		if msgs := conv.GetMessages(); len(msgs) > 0 {
			wm := msgs[0].GetMessage()
			if wm != nil {
				c.Timestamp = int64(wm.GetMessageTimestamp())
				c.FromMe = wm.GetKey().GetFromMe()
				c.LastMessage = extractText(wm.GetMessage())
				if c.LastMessage == "" {
					c.LastMessage = describeMessage(wm.GetMessage())
				}
			}
		}
		chats = append(chats, c)
	}
	if len(chats) > 0 {
		br.emit(map[string]interface{}{"type": "chats", "chats": chats})
	}
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
	_, _ = br.client.SendMessage(ctx, jid, msg)
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
