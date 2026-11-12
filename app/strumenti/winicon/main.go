// winicon crea un file .syso (oggetto COFF con sezione .rsrc) che contiene un'icona,
// così il linker di Go la incorpora nell'eseguibile Windows.
// Uso: go run ./strumenti/winicon -o rsrc_windows_amd64.syso icona16.png icona32.png ...
// Le immagini devono essere PNG quadrati (Windows Vista e successivi accettano PNG nelle icone).
package main

import (
	"bytes"
	"encoding/binary"
	"flag"
	"image/png"
	"log"
	"os"
)

const (
	rtIcon      = 3
	rtGroupIcon = 14
	lingua      = 0x0409
	idGruppo    = 1
)

func main() {
	out := flag.String("o", "rsrc_windows_amd64.syso", "file .syso da scrivere")
	flag.Parse()
	if flag.NArg() == 0 {
		log.Fatal("servono uno o più PNG")
	}

	type img struct {
		dati []byte
		lato int
	}
	var imgs []img
	for _, f := range flag.Args() {
		b, err := os.ReadFile(f)
		if err != nil {
			log.Fatal(err)
		}
		cfg, err := png.DecodeConfig(bytes.NewReader(b))
		if err != nil {
			log.Fatalf("%s: %v", f, err)
		}
		if cfg.Width != cfg.Height || cfg.Width > 256 {
			log.Fatalf("%s: serve un PNG quadrato fino a 256 px", f)
		}
		imgs = append(imgs, img{b, cfg.Width})
	}

	// GRPICONDIR + GRPICONDIRENTRY per ogni immagine
	var grp bytes.Buffer
	w := func(v any) { binary.Write(&grp, binary.LittleEndian, v) }
	w(uint16(0))
	w(uint16(1))
	w(uint16(len(imgs)))
	for i, im := range imgs {
		lato := uint8(im.lato)
		if im.lato == 256 {
			lato = 0
		}
		w(lato)
		w(lato)
		w(uint8(0))
		w(uint8(0))
		w(uint16(1))
		w(uint16(32))
		w(uint32(len(im.dati)))
		w(uint16(i + 1))
	}

	// Albero delle risorse: radice → tipo → id → lingua → voce dati.
	// Layout: [radice][dir tipo ICON][dir tipo GROUP][dir lingua per ogni voce][voci dati][dati]
	type risorsa struct {
		tipo, id int
		dati     []byte
	}
	var ris []risorsa
	for i, im := range imgs {
		ris = append(ris, risorsa{rtIcon, i + 1, im.dati})
	}
	ris = append(ris, risorsa{rtGroupIcon, idGruppo, grp.Bytes()})

	const dirHdr, dirEnt, dataEnt = 16, 8, 16
	nIcon := len(imgs)
	offRadice := 0
	offTipoIcon := offRadice + dirHdr + 2*dirEnt
	offTipoGroup := offTipoIcon + dirHdr + nIcon*dirEnt
	offLingue := offTipoGroup + dirHdr + 1*dirEnt
	offVoci := offLingue + len(ris)*(dirHdr+dirEnt)
	offDati := offVoci + len(ris)*dataEnt

	var sez bytes.Buffer
	sw := func(v any) { binary.Write(&sez, binary.LittleEndian, v) }
	dir := func(nId int) {
		sw(uint32(0))
		sw(uint32(0))
		sw(uint16(0))
		sw(uint16(0))
		sw(uint16(0))
		sw(uint16(nId))
	}
	sotto := func(off int) uint32 { return uint32(off) | 0x80000000 }

	dir(2)
	sw(uint32(rtIcon))
	sw(sotto(offTipoIcon))
	sw(uint32(rtGroupIcon))
	sw(sotto(offTipoGroup))

	dir(nIcon)
	for i := 0; i < nIcon; i++ {
		sw(uint32(ris[i].id))
		sw(sotto(offLingue + i*(dirHdr+dirEnt)))
	}
	dir(1)
	sw(uint32(idGruppo))
	sw(sotto(offLingue + nIcon*(dirHdr+dirEnt)))

	for i := range ris {
		dir(1)
		sw(uint32(lingua))
		sw(uint32(offVoci + i*dataEnt)) // voce dati: senza bit alto
	}

	// voci dati: OffsetToData è un RVA, va rilocato rispetto all'inizio della sezione
	var reloc []uint32
	offCorrente := offDati
	var datiTutti bytes.Buffer
	for _, r := range ris {
		reloc = append(reloc, uint32(sez.Len()))
		sw(uint32(offCorrente))
		sw(uint32(len(r.dati)))
		sw(uint32(0))
		sw(uint32(0))
		datiTutti.Write(r.dati)
		for datiTutti.Len()%8 != 0 {
			datiTutti.WriteByte(0)
		}
		offCorrente = offDati + datiTutti.Len()
	}
	if sez.Len() != offDati {
		log.Fatalf("layout errato: %d != %d", sez.Len(), offDati)
	}
	sez.Write(datiTutti.Bytes())

	// File COFF: header, una sezione, rilocazioni, tabella simboli (un simbolo di sezione), tabella stringhe vuota
	const coffHdr, sezHdr, relSize, symSize = 20, 40, 10, 18
	offRaw := coffHdr + sezHdr
	offRel := offRaw + sez.Len()
	offSym := offRel + len(reloc)*relSize

	var f bytes.Buffer
	fw := func(v any) { binary.Write(&f, binary.LittleEndian, v) }
	fw(uint16(0x8664)) // AMD64
	fw(uint16(1))
	fw(uint32(0))
	fw(uint32(offSym))
	fw(uint32(1))
	fw(uint16(0))
	fw(uint16(0))

	f.WriteString(".rsrc\x00\x00\x00")
	fw(uint32(0))
	fw(uint32(0))
	fw(uint32(sez.Len()))
	fw(uint32(offRaw))
	fw(uint32(offRel))
	fw(uint32(0))
	fw(uint16(len(reloc)))
	fw(uint16(0))
	fw(uint32(0x40000040)) // dati inizializzati, lettura

	f.Write(sez.Bytes())
	for _, r := range reloc {
		fw(r)
		fw(uint32(0))      // simbolo 0 = .rsrc
		fw(uint16(0x0003)) // IMAGE_REL_AMD64_ADDR32NB
	}
	f.WriteString(".rsrc\x00\x00\x00")
	fw(uint32(0))
	fw(int16(1))
	fw(uint16(0))
	fw(uint8(3)) // IMAGE_SYM_CLASS_STATIC
	fw(uint8(0))
	fw(uint32(4)) // tabella stringhe vuota

	if err := os.WriteFile(*out, f.Bytes(), 0o644); err != nil {
		log.Fatal(err)
	}
}
