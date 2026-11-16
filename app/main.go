// Secret Santa di famiglia: un piccolo eseguibile che contiene la pagina web,
// la apre nel browser predefinito e salva i dati in un file JSON accanto all'app.
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
)

//go:embed web/index.html
var paginaHTML []byte

const (
	portaPreferita = 47823
	nomeFileDati   = "secret-santa-dati.json"
	nomeFileBak    = "secret-santa-dati.bak.json"
	maxDati        = 5 << 20
	// la pagina manda un battito ogni 15 s; i browser rallentano i timer delle schede in background
	// fino a uno al minuto, quindi aspetto parecchio prima di considerare la pagina chiusa
	timeoutInattivita  = 3 * time.Minute
	attesaDopoChiusura = 8 * time.Second
)

type app struct {
	dirDati string

	mu              sync.Mutex
	ultimoContatto  time.Time
	chiusuraChiesta time.Time
	bakFatto        bool
}

func main() {
	dir, err := cartellaDati()
	if err != nil {
		fatale("Non trovo una cartella in cui salvare i dati: %v", err)
	}
	log.SetOutput(apriLog(dir))
	log.Printf("avvio, dati in %s", dir)

	a := &app{dirDati: dir, ultimoContatto: time.Now()}

	// SECRET_SANTA_PORTA serve per le prove: una copia di prova gira su un'altra porta e,
	// se quella porta è occupata, si ferma invece di agganciarsi all'app vera già aperta.
	porta0, prova := portaPreferita, false
	if v := os.Getenv("SECRET_SANTA_PORTA"); v != "" {
		if _, err := fmt.Sscan(v, &porta0); err != nil {
			fatale("SECRET_SANTA_PORTA non valida: %q", v)
		}
		prova = true
	}
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", porta0))
	if err != nil {
		if prova {
			fatale("Porta di prova %d occupata: %v", porta0, err)
		}
		// probabilmente l'app è già aperta: in quel caso riapro solo la pagina
		url := fmt.Sprintf("http://127.0.0.1:%d/", porta0)
		if giaAperta(url) {
			apriBrowser(url)
			return
		}
		ln, err = net.Listen("tcp", "127.0.0.1:0")
		if err != nil {
			fatale("Non riesco ad avviare il server locale: %v", err)
		}
	}
	porta := ln.Addr().(*net.TCPAddr).Port
	url := fmt.Sprintf("http://127.0.0.1:%d/", porta)

	mux := http.NewServeMux()
	mux.HandleFunc("/", a.pagina)
	mux.HandleFunc("/api/dati", a.dati)
	mux.HandleFunc("/api/ping", a.ping)
	mux.HandleFunc("/api/chiudi", a.chiudi)
	srv := &http.Server{Handler: a.soloLocale(porta, mux), ReadHeaderTimeout: 10 * time.Second}
	esci := func(motivo string) {
		log.Printf("chiusura: %s", motivo)
		ctx, annulla := context.WithTimeout(context.Background(), 2*time.Second)
		defer annulla()
		srv.Shutdown(ctx)
		os.Exit(0)
	}
	mux.HandleFunc("/api/esci", func(w http.ResponseWriter, r *http.Request) {
		// l'intestazione personalizzata impedisce a un altro sito di chiudere l'app (serve un preflight CORS)
		if r.Method != http.MethodPost || r.Header.Get("X-Secret-Santa") != "1" {
			http.Error(w, "richiesta non ammessa", http.StatusForbidden)
			return
		}
		w.WriteHeader(http.StatusNoContent)
		go func() { time.Sleep(300 * time.Millisecond); esci("pulsante Chiudi nella pagina") }()
	})

	// il lanciatore Mac (e Ctrl+C in un terminale) chiedono la chiusura con un segnale
	segnali := make(chan os.Signal, 1)
	signal.Notify(segnali, os.Interrupt, syscall.SIGTERM)
	go func() { esci(fmt.Sprint("segnale ", <-segnali)) }()

	// il lanciatore Mac legge l'indirizzo da qui per riaprire la pagina dal Dock
	fmt.Println("URL=" + url)

	go a.sorveglia()
	if os.Getenv("SECRET_SANTA_NO_BROWSER") == "" { // usato solo per le prove
		go apriBrowser(url)
	}
	log.Printf("in ascolto su %s", url)
	if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
		fatale("Server interrotto: %v", err)
	}
}

// soloLocale accetta solo richieste indirizzate a 127.0.0.1/localhost (protezione dal DNS rebinding)
// e aggiorna il momento dell'ultimo contatto con la pagina.
func (a *app) soloLocale(porta int, next http.Handler) http.Handler {
	ammessi := map[string]bool{
		fmt.Sprintf("127.0.0.1:%d", porta): true,
		fmt.Sprintf("localhost:%d", porta): true,
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !ammessi[r.Host] {
			http.Error(w, "host non ammesso", http.StatusForbidden)
			return
		}
		a.mu.Lock()
		a.ultimoContatto = time.Now()
		// una pagina (ri)caricata o ancora viva annulla la chiusura; il salvataggio finale no
		switch r.URL.Path {
		case "/", "/index.html", "/api/ping":
			a.chiusuraChiesta = time.Time{}
		}
		a.mu.Unlock()
		next.ServeHTTP(w, r)
	})
}

func (a *app) pagina(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" && r.URL.Path != "/index.html" {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Write(paginaHTML)
}

func (a *app) dati(w http.ResponseWriter, r *http.Request) {
	percorso := filepath.Join(a.dirDati, nomeFileDati)
	switch r.Method {
	case http.MethodGet:
		b, err := os.ReadFile(percorso)
		if errors.Is(err, os.ErrNotExist) {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "no-store")
		w.Write(b)

	case http.MethodPut:
		b, err := io.ReadAll(http.MaxBytesReader(w, r.Body, maxDati))
		if err != nil {
			http.Error(w, err.Error(), http.StatusRequestEntityTooLarge)
			return
		}
		var verifica struct {
			Nuclei []json.RawMessage `json:"nuclei"`
		}
		if err := json.Unmarshal(b, &verifica); err != nil || verifica.Nuclei == nil {
			http.Error(w, "dati non validi", http.StatusBadRequest)
			return
		}
		if err := a.scrivi(percorso, b); err != nil {
			log.Printf("salvataggio fallito: %v", err)
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.WriteHeader(http.StatusNoContent)

	default:
		http.Error(w, "metodo non ammesso", http.StatusMethodNotAllowed)
	}
}

// scrivi salva in modo atomico; al primo salvataggio della sessione conserva la versione precedente nel .bak.
func (a *app) scrivi(percorso string, b []byte) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	if !a.bakFatto {
		if vecchio, err := os.ReadFile(percorso); err == nil {
			if err := os.WriteFile(filepath.Join(a.dirDati, nomeFileBak), vecchio, 0o644); err != nil {
				return fmt.Errorf("backup: %w", err)
			}
		}
		a.bakFatto = true
	}
	tmp := percorso + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, percorso)
}

func (a *app) ping(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("X-Secret-Santa", "1")
	w.WriteHeader(http.StatusNoContent)
}

func (a *app) chiudi(w http.ResponseWriter, r *http.Request) {
	a.mu.Lock()
	a.chiusuraChiesta = time.Now()
	a.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

// sorveglia chiude l'app quando la pagina è stata chiusa (o non si fa sentire da troppo tempo).
func (a *app) sorveglia() {
	for range time.Tick(2 * time.Second) {
		a.mu.Lock()
		chiusa := !a.chiusuraChiesta.IsZero() && time.Since(a.chiusuraChiesta) > attesaDopoChiusura
		inattiva := time.Since(a.ultimoContatto) > timeoutInattivita
		a.mu.Unlock()
		if chiusa || inattiva {
			log.Printf("chiusura (pagina chiusa: %v, inattiva: %v)", chiusa, inattiva)
			os.Exit(0)
		}
	}
}

// cartellaDati è la cartella che contiene l'eseguibile (o il pacchetto .app su Mac).
// Se non è scrivibile (per esempio un'app avviata da un'immagine disco) usa Documenti/Secret Santa.
func cartellaDati() (string, error) {
	exe, err := os.Executable()
	if err == nil {
		if p, e := filepath.EvalSymlinks(exe); e == nil {
			exe = p
		}
		dir := filepath.Dir(exe)
		if i := strings.Index(dir, ".app/Contents/MacOS"); i >= 0 {
			dir = filepath.Dir(dir[:i+len(".app")])
		}
		if !strings.Contains(dir, "AppTranslocation") && scrivibile(dir) {
			return dir, nil
		}
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	dir := filepath.Join(home, "Documents", "Secret Santa")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return dir, nil
}

func scrivibile(dir string) bool {
	f, err := os.CreateTemp(dir, ".secret-santa-prova-*")
	if err != nil {
		return false
	}
	f.Close()
	os.Remove(f.Name())
	return true
}

func apriLog(dir string) io.Writer {
	f, err := os.OpenFile(filepath.Join(dir, "secret-santa.log"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o644)
	if err != nil {
		return io.Discard
	}
	return f
}

func giaAperta(url string) bool {
	c := http.Client{Timeout: 2 * time.Second}
	r, err := c.Post(url+"api/ping", "text/plain", nil)
	if err != nil {
		return false
	}
	r.Body.Close()
	return r.Header.Get("X-Secret-Santa") == "1"
}

func apriBrowser(url string) {
	var cmd *exec.Cmd
	switch runtime.GOOS {
	case "darwin":
		cmd = exec.Command("open", url)
	case "windows":
		cmd = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
	default:
		cmd = exec.Command("xdg-open", url)
	}
	if err := cmd.Start(); err != nil {
		log.Printf("apertura browser fallita: %v", err)
	}
}

func fatale(formato string, args ...any) {
	msg := fmt.Sprintf(formato, args...)
	log.Print(msg)
	mostraErrore(msg)
	os.Exit(1)
}

// mostraErrore avvisa l'utente anche senza terminale.
func mostraErrore(msg string) {
	switch runtime.GOOS {
	case "darwin":
		script := fmt.Sprintf(`display alert "Secret Santa" message %q as critical`, msg)
		exec.Command("osascript", "-e", script).Run()
	case "windows":
		ps := fmt.Sprintf(`Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('%s','Secret Santa')`,
			strings.ReplaceAll(msg, "'", "''"))
		exec.Command("powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", ps).Run()
	default:
		fmt.Fprintln(os.Stderr, msg)
		// avviato dal menu delle applicazioni non c'è un terminale: provo con le finestre del desktop
		for _, c := range [][]string{
			{"zenity", "--error", "--title=Secret Santa", "--text=" + msg},
			{"kdialog", "--title", "Secret Santa", "--error", msg},
			{"notify-send", "Secret Santa", msg},
		} {
			if _, err := exec.LookPath(c[0]); err == nil {
				exec.Command(c[0], c[1:]...).Run()
				return
			}
		}
	}
}
