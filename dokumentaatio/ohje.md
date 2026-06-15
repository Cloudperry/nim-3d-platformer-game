# Sovelluksen release version suorittaminen ja testien ajaminen (helpompi kuin projektin compilaus)

1. Lataa pelin pakattu release etsimällä [täältä](https://github.com/Cloudperry/nim-3d-platformer-game/releases) uusimman version .tar.xz tiedosto
2. Pura release komennolla `archive="<release name>.tar.xz" && tar -xJf "$archive" && cd "${archive%.tar.xz}"` tai haluamallasi graafisella työkalulla
3. Pelin voi suorittaa komennolla `./platformer-game` terminaalissa, jonka työkansio on purettu release versio
4. Testit voi suorittaa komennolla `./tests/platformer-game-replay-tests`

# Pelin kontrollit

Peliä pelataan näppäimistöllä ja hiirellä. Pelissä on sekä QWERTY että Dvorak kontrollit.

| Toiminto | QWERTY | Dvorak |
| --- | --- | --- |
| Kävele eteen | W | , |
| Kävele taakse | S | O |
| Kävele vasemmalle | A | A |
| Kävele oikealle | D | E |
| Hyppy / seinähyppy | välilyönti | välilyönti |
| Lennä alas (lentotila) | vasen Shift | vasen Shift tai ' |
| Käännä kameraa | hiiri | hiiri |

Kävelytilassa (`Walking`) pelaaja liikkuu kuin FPS-pelissä ja hyppynapilla voi tehdä myös seinähyppyjä. Pelaaja hyppää automaattisesti osuessaan maahan/seinään, jos välilyöntiä pitää pohjassa. Lentotilassa (`Flying`) kamera lentää vapaasti ja Shiftillä (tai `'`) pääsee alaspäin.

Pelin voi sulkea painamalla Esc ja pelin saa fullscreen -tilaan painamalla Alt + Enter.

# Uusintojen katsominen ja tallentaminen

- Peli osaa tallentaa/toistaa uusintoja pelauksesta
- Voit katsoa pelin testidatassa olevia uusintoja esim. komennolla `./platformer-game --replayName=testData/jumpTest1` tai `./platformer-game --replayName=testData/walljumpParkourTest1`
- Voit tallentaa pelaamisesta uusinnan komennolla `./platformer-game --recordInputs` ja sulkemalla lopuksi pelin. Uusinta tallennetaan pelin suorituskansioon. Uusinnan nimeksi tulee päivämäärä ja kellonaika. 
- Tällä hetkellä peli renderöi näytön virkistystaajuudella, mutta simulaatio etenee uusintaa katsoessa sen määrittämällä nopeudella. Siksi esim. 60 hz näytöllä äänitetty uusinta näytettäisiin 2x nopeammin 120 hz näytöllä. 
- Repositoriossa olevat uusinnat ovat 60 hz, joten ne näkyvät normaalilla nopeudella 60 hz näytöllä  

# Pelin asetukset

Asetukset annetaan komentoriviparametreina pelin käynnistyksen yhteydessä. Esim. `./platformer-game --movementMode=Flying --mouseSensitivity=3`. Kaikki vaihtoehdot ja niiden oletusarvot näkee myös komennolla `./platformer-game --help`.

| Asetus | Arvot (oletus) | Mitä tekee |
| --- | --- | --- |
| `movementMode` | `Walking` / `Flying` (`Walking`) | Liikkumistila. `Walking` = FPS-pelin kontrollit, `Flying` = vapaasti lentävä kamera. |
| `mouseSensitivity` | desimaaliluku (`2.0`) | Kameran kääntönopeus. |
| `recordInputs` | `true` / `false` (`false`) | Nauhoittaa pelaajan syötteistä uusinnan tiedostoina. |
| `replayName` | nimi (tyhjä) | Toistaa annetun nimisen uusinnan tiedostoista. Tiedostoja on useita ja uusinnan nimi on osa ennen ensimmäistä pistettä. |
| `slangBinPath` | polku (tyhjä) | Slang-shaderkääntäjän binäärin kansio. Tyhjänä `slangc` haetaan käyttäjän PATHista. |
| `swapInterval` | `0` / `1` / `2` (`1`) | VSync. `0` = pois päältä, `1` = päällä, `2` = päällä puolella virkistystaajuudella. |
| `compileShadersAndQuit` | `true` / `false` (`false`) | Kääntää shaderit ja sulkee pelin heti perään. Käytetään release version luonnissa. |

Huom: uusintaa toistaessa peli käyttää uusinnan mukana tallennettua konfiguraatiota, jotta toisto menee samoilla asetuksilla kuin nauhoitettaessa.

Shaderit käännetään uudelleen vain debug-buildeissa, joten ladatussa release versiossa asetuksia `slangBinPath` ja `compileShadersAndQuit` ei tarvitse.

# Testin luominen uusinnasta

Pelin mukana tulee työkalu testien luomiseen ja suorittamiseen. Testiä luodessa työkalu ottaa syötteenä uusintatiedostojen polun (ilman tiedostopäätteitä). Sen jälkeen työkalu kysyy nimeä, jolla testi ja siihen liittyvät uusintatiedostot tallennetaan kansion `testData` alle. Testiä suorittaessa työkalu ottaa syötteenä `testData` kansiossa olevan testin nimen ilman tiedostopäätettä. Testiä ajaessa työkalu tulostaa joko `true` tai `false` sen mukaan, meneekö testi läpi.

Testin luonti:
1. Tallenna uusinta avaamalla peli komennolla `./platformer-game --recordInputs` ja sulkemalla lopuksi peli
2. Tallenna uusinnasta testi komennolla `./platformer-game-tester makeTest --replayName=<nimi>`, jossa nimi voisi olla esim. `2026-6-12-9-33-44`. Testin luominen siirtää uusintatiedostot testData kansioon käyttäjän syöttämällä nimellä.

Yksittäisen testin voi suorittaa testaustyökalun komennolla `./platformer-game-tester runTest --testName=<nimi>`

# Kääntäminen lähdekoodista

1. Asenna Nim Choosenim -työkalun avulla [näillä ohjeilla](https://nim-lang.org/install_unix.html)
2. Lataa Slang shader compiler [täältä](https://github.com/shader-slang/slang/releases/) ja lisää sen bin kansio `PATH` ympäristömuuttujaan
2. Kloonaa repositorio komennolla `git clone https://github.com/Cloudperry/nim-3d-platformer-game.git && cd nim-3d-platformer-game`
3. Suorita repositorion kansiossa komento `nimble install` asentaaksesi sovelluksen oman käyttäjän kotikansion alle tai `nimble releaseBuild` luodaksesi suoritettavan binäärin repositorioon `bin` kansion alle
4. Pelin suorittaminen, uusintojen tallentaminen sekä yksittäisen testin luonti/suorittaminen onnistuu samoilla komennoilla kuin aikaisemmissa ohjeissa, mutta `./platformer-game` ja `./platformer-game-test` polun eteen laitetaan bin kansio (esim. ``./bin/platformer-game``)
5. Kaikki testit voi suorittaa komennolla `nimble test` samassa kansiossa
