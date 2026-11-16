# 🎄 Secret Santa di famiglia

Una piccola app per organizzare il Secret Santa di Natale in famiglia: inserisci fratelli e sorelle con coniugi e figli, decidi chi fa i regali e quanti regali deve ricevere ognuno, poi estrai gli abbinamenti a caso.

<img src="app/icona/mac-1024.png" width="128" alt="Icona di Secret Santa">

## Cosa fa

- **Famiglia divisa in nuclei**: ogni fratello o sorella con il proprio coniuge e i figli.
- **Chi fa regali e chi li riceve soltanto**: per esempio i bimbi piccoli ricevono senza partecipare.
- **Regali da ricevere per persona**: a qualcuno 1 regalo, a qualcun altro 2 o più.
- **Sorteggio casuale con regole**:
  - nessuno fa un regalo a sé stesso;
  - nessuno fa due regali alla stessa persona;
  - (facoltativo) nessuno fa regali a chi è nel proprio nucleo.
  I regali da fare sono divisi il più equamente possibile tra chi partecipa.
- **Risultati segreti**: ognuno clicca sulla propria scheda per scoprire a chi fa i regali.
- **Dati salvati in automatico** in `secret-santa-dati.json` accanto all'app, con una copia `.bak` della versione precedente; si possono esportare e importare come backup.

## Come si usa

Scarica l'app per il tuo sistema e aprila con un doppio clic: si apre la pagina nel browser predefinito.

- **Mac** (macOS 13 o successivo, Intel e Apple Silicon): finché è aperta l'app ha l'icona nel Dock. Un clic sull'icona riapre la pagina; **Esci** (o ⌘Q) la chiude.
- **Windows** (64 bit): `SecretSanta.exe`.
- **Linux** (amd64 o arm64): estrai l'archivio nella cartella dove vuoi tenerla e lancia una volta `./installa.sh` per aggiungere Secret Santa al menu delle applicazioni, con l'icona. In alternativa avvialo con `./secret-santa`.

In tutti i casi il pulsante **⏻ Chiudi Secret Santa** nella pagina salva e chiude l'app, che comunque si chiude da sola poco dopo aver chiuso la scheda.

Mettila in una cartella tutta sua (per esempio `Documenti/Secret Santa`): il file dei dati viene creato accanto all'app.

### Primo avvio

Le app non sono firmate da uno sviluppatore registrato, quindi il sistema chiede conferma la prima volta:

- **Mac**: tasto destro sull'app → **Apri** → **Apri** (oppure Impostazioni di Sistema → Privacy e sicurezza → **Apri comunque**).
- **Windows**: nella schermata "Windows ha protetto il PC" → **Ulteriori informazioni** → **Esegui comunque**.

### Senza installare nulla

`index.html` funziona anche da solo, aperto direttamente nel browser: in quel caso i dati restano salvati nel browser invece che in un file.

## Compilare

Serve un Mac con [Go](https://go.dev) 1.25+ e gli strumenti da riga di comando di Xcode (per Swift, `lipo`, `iconutil`, `codesign`).

```bash
./app/build.sh            # compila Mac, Windows e Linux in dist/
./app/build.sh --icone    # ridisegna anche le icone da app/icona/disegna.swift
```

Risultati in `dist/`: `Secret Santa - Mac.zip`, `Secret Santa - Windows.zip`, `Secret Santa - Linux amd64.tar.gz` e `Secret Santa - Linux arm64.tar.gz`.

## Com'è fatto

| Parte | Descrizione |
|---|---|
| `index.html` | Tutta l'interfaccia e il sorteggio, in un solo file HTML/JS senza dipendenze. |
| `app/main.go` | Programma Go (solo libreria standard) che incorpora la pagina, la serve su `127.0.0.1`, apre il browser e salva i dati nel file JSON. Accetta solo richieste locali. |
| `app/mac/Lanciatore.swift` | Lanciatore macOS: icona nel Dock, riapertura della pagina, **Esci**. |
| `app/linux/installa.sh` | Aggiunge Secret Santa al menu delle applicazioni su Linux (file `.desktop` dell'utente). |
| `app/icona/disegna.swift` | Disegna l'icona; `build.sh` ne ricava `.icns` per Mac e le risorse per Windows. |
| `app/strumenti/winicon` | Piccolo generatore del file `.syso` che incorpora l'icona nell'eseguibile Windows. |

## Licenza

Rilasciato con licenza [MIT](LICENSE): puoi usarlo, modificarlo e ridistribuirlo liberamente, mantenendo l'nota di copyright.
