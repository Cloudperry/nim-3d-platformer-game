# Testausdokumentti

Peliä testataan tällä hetkellä lähinnä automaattisilla end-to-end -testeillä, jotka ajavat pelin simulaatiota pelaamisesta äänitettyjen uusintojen avulla. Kunnollista testikattavuuden mittausta on hankala toteuttaa Nim projektille, joten tässä dokumentissa keskitytään testattuihin ja testaamattomiin moduuleihin ja toiminnallisuuksiin. Repositorion dev branchillä on yksikkötestin kaltainen replay järjestelmään testi, joka tarkistaa että uusinnan toistamisen ja uudelleentallentamisen jälkeen uusinnan sisältö pysyy samana. Testi ei one vielä tarpeeksi hyvä release versioon, ja sen takia jätin sen dev branchille. 

## Automaattinen testaus

Pelisimulaation regressiotestit on toteutettu tiedostossa [tests/GameSimulationTests.nim](../tests/GameSimulationTests.nim) ja varsinainen testauslogiikka on [src/Tester.nim](../src/Tester.nim) moduulissa.  Uusintoihin perustuvat simulaation regressiotestit toimivat niin, että testidatasta luetaan pelin alkutila ja sen jälkeen peliä simuloidaan uusinnan avulla. Uusinnan loputtua pelin lopputilaa verrataan testidatassa tallennettuun tilaan. Näin testit varmistavat että pelin simulaatioon ei ole tehty muutoksia vahingossa ja, että simulaatio toimii joka kerta samalla tapaa samoilla syötteillä.

Lisäksi replay järjestelmää varten on yksikkötestin kaltainen testi tiedostossa [tests/ReplaySystemTests.nim](../tests/ReplaySystemTests.nim). Testi toistaa uusinnan ilman pelisimulaatiota ja tallentaa toistetun uusinnan uudestaan. Testi varmistaa, että uusintojen toistaminen ja tallentaminen toimii deterministisesti. Samalla testi varmistaa, että uusintojen toistaminen ja tallentaminen toimii.

### Mitä testataan

Koska testit ajavat koko pelin simulaatiosilmukan, ne kattavat suuren osan pelilogiikasta:

- **GameLogic**: simulaation alustus, päivityssilmukka (`preUpdate`/`update`) ja siivous
- **SceneLogic**: 3D-ympäristön ja olioiden (Entity) päivittäminen
- **PlayerController**: pelaajan käveleminen, hyppiminen, painovoima ja seinähypyt
- **Physics**: koordinaattiakselien suuntaisten laatikoiden (AABB) törmäysten ratkaisu
- **CameraController**: kameran kääntäminen sekä lentävän kameran liike
- **Input**: uusintojen tallennus ja toisto sekä syötteiden determinismi

Eri testit painottavat eri toiminnallisuuksia: `jumpTest`-testit kattavat hyppimisen ja painovoiman, `walljumpParkourTest`-testit tarkat seinähypyt ja useiden seinien kautta peräkkäin hyppäämisen, ja `flyingCameraTest1` lentävän kameran liikkeen.

### Mitä ei testata

Seuraavat moduulit jäävät testaamatta, koska ne eivät kuulu pelin simulaatioon vaan renderöintiin tai työkaluihin:

- **Game**: pelin ikkunan luonti, renderöinti ja syötteiden lukeminen GLFW:llä. Tämä on pelin ulkokuori eikä deterministinen osa simulaatiota.
- **GlUtils**: itse tehty OpenGL-abstraktio, jota käytetään vaan renderöintiin
- **SceneBuilder**: 3D-mallien geometrian generointi renderöintiä varten. Mallien luonti ajetaan testien yhteydessä, mutta generoituja 3D-malleja ei tarkisteta.
- **Slangc**: Slang-shaderkääntäjää kutsuva apukirjasto, jota käytetään vain peliä kehittäessä.
- **Logger**: terminaaliin lokitus ja viimisellä rivillä näkyvän suorituskykystatistiikan piirtäminen.

## Sovellukseen jääneet laatuongelmat

Testit nojaavat tällä hetkellä käsin tallennettuihin uusintoihin, joten ne huomaavat vain regressiot olemassa olevissa pelitilanteissa. Yksikkötestausta voisi olla enemmänkin. Tällä hetkellä vain replay järjestelmälle on yksikkötestejä, mutta esim. pelin fysiikkoja, pelaajan liikkumista ja kameraa varten ei ole yksikkötestejä. 