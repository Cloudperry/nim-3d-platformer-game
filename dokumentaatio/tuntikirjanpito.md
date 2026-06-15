# Tuntikirjanpito

- 5.9.2025 1h Aloitettu projekti ja tehty kirjastojen hakua ja OpenGL pohja valmiista esimerkistä.

- 8.9.2025 3h Tehty parempi OpenGL pohja learnopengl harjoitusten perusteella ja otettu käyttöön Slang shader kieli.

- 9.9.2025 5h OpenGL harjoittelua ja abstraktioiden kehittämistä OpenGL:n tärkeimpiä ominaisuuksia varten

- 12.9.-13.9.2025 6h Korjattu OpenGL abstraktiota, laitettu projekti gittiin ja lisätty 3D mallin sijainnin/suunnan/skaalan muuttaminen

- 15.9.2025 4h Lisätty fullscreen toggle ja kamera objekti, jota voi liikuttaa muttei kääntää. Valmisteltu first person kameran toteutusta lukitsemalla/piilottamalla kursori.

- 16.9.2025 4h Lisätty kunnollinen first person kamera, jolla voi lentää vapaasti ja kääntyä hiirellä. Tehty 3D scenen luontiin objekteja ja valmisteltu scenen renderöintiä sekä valaistusta.

- 17.9.2025 4h Lisätty suuntaan perustuva "auringon kaltainen" valaistus. Lisätty OpenGL abstraktioon ominaisuuksia.

- 18.9.2025 3.5h Lisätty OpenGL abstraktioon ominaisuuksia yksittäisten objektin kenttien päivittämiseksi GPU:lle ja korjattu suuntaan perustuvaa valaistusta.

- 19.9.2025 4h Korjattu lentävän kameran bugeja. Lisätty kirjasto performance lokitukseen, joka näyttää pelin suorituskyvyn aina terminaalin pohjimmaisella rivillä ja muut lokit näkyvät sen yläpuolella. Laitettu OpenGL virheiden lokitus näkyviin vain debug buildeissä.

- 20.9.2025 5h Lisätty OpenGL:n vaatiman muistijärjestyksen objekteja generoiva makro. Se lukee Nim objektin ja lisää siihen OpenGL:n vaatimat tyhjät "padding" osiot kenttien väliin. Paranneltu Slang shader compileria kutsuvan kirjaston konfiguroitavuutta. Valmisteltu monia esineitä sisältävien ympäristöjen renderöintiä.

- 22.9.2025 4.5h Lisätty kirjasto 3D esineiden kuten kuutio, pallo ja pyramidi generointiin. Siirrytty kovakoodatuista 3D malleista kirjaston generoimiin. Lisätty tuki useiden 3D mallien renderöinnille. Siirretty loggauskoodi omaan moduuliin ja siistitty globaalin tilan hallintaa.

- 30.9.2025 1h Lisätty listamaisten kenttien siirtäminen GPU:lle OpenGL abstraktioon

- 20.5.2026 2h Luotu uusi repo, jossa ei ole enää sphere tracing / SDF projektin koodia. Korjattu projektia niin että se toimii uusimmilla Nim versioilla. Vaihdettu automaattinen CLI argumenttien parsinta kirjastoon, joka tukee samalla myös konfiguraatiotiedostojen parsintaa.

- 21.5.2026 5h Lisätty pallomaiset valot (point lights) ja valojen heijastukset (specular lighting). Valmisteltu liikkumista kävelemällä ja törmäysten havaitsemista. Kirjoitettu AI:n generoimat muotojen 3D-mallin luontifunktiot uudelleen.

- 22.5.2026 3h Paranneltu laatikoiden törmäysten havaitsemista. Lisätty pelaajan käveleminen maan päällä ja hieman rikkinäinen hyppäys/painovoima.

- 24.5.2026 1h Korjattu hyppäys/painovoima. Nyt pelaaja voi hyppiä tasanteilla ja putoaa, jos alla ei ole tasannetta. Seinään törmäys ei ole vielä tässä versiossa.

- 25.5.2026 5h Lisätty kunnollinen törmäysten ratkaisija koordinaattiakselien suuntaisia laatikoita (AABB) varten. Tehty pelaajan käveleminen, hyppiminen ja painovoima uudelleen törmäysten ratkaisijaa hyödyntäen. Nyt pelaaja törmää seinään eikä mene sen läpi. Hyppiminen toimii myös paremmin (esim. pelaaja ei voi leijua ylöspäin, kun seinä on vieressä). Suunniteltu uutta suuntaa projektille. Aikaisemmin projektin oli tarkoitus olla yksinkertainen first person shooter. Päätin alkaa tekemään projektista ensimmäisen persoonan tasohyppelypeliä.

- 26.5.2026 2.5h Lisätty yksinkertainen seinähyppy ja paranneltu hyppimisen rajoittamiseen liittyvää logiikkaa. Seinähypyllä voi hypätä uudestaan koskettaessa seinään. Seinähypyn olisi tarkoitus hypätä seinästä pois päin, mutta tällä hetkellä vaakasuuntaisen liikkeen logiikka peruu heti seinähypystä saadun vaakasuuntaisen nopeuden.

- 28.5.2026 1.5h Muutettu pelaajan liike Counter-strike 1.6:een pohjautuvaan järjestelmään. Pelaajan liike toimii nyt kiihdytyksen ja kitkan avulla. Seinähypyt toimivat myös paremmin tässä järjestelmässä, koska "kävelyjärjestelmä" ei nollaa vaakasuuntaista vauhtia seinähypystä.

- 29.5.2026 3h Tehty pelaajaan, kameraan ja törmäysten tarkistusteen liittyvien järjestelmien uudelleenkirjoittamista. Aikaisemmin kaikki näistä olivat omia objektejaan, joita varten oli käsin kirjoitettu koodia esim. pelin update ja draw silmukoissa. Nyt olisi tarkoitus siirtää kaikki toiminnallisuudet yhden objektin alle. Objektilla on kind kenttä, joka kertoo sen tyypin (esim. pelaaja tai laatikko). Objektin toteuttamien komponenttien toiminnallisuudet toteutetaan yhdessä update funktiossa, joka kutsuu objektin tyypistä riippuen sen omaa update funktiota. Tämänkaltaista lähestymistapaa kutsutaan yleensä peleissä nimellä megastruct. Tässä pelissä se tulee mahdollistamaan esim. eri skriptattavien esineiden vuorovaikutuksen toistensa kanssa helpommin ja modulaarisemmin.

- 1.6.2026 8h Korjattu edellisestä uudelleenkirjoituksesta aiheutuneet bugit ja paranneltu "Entity" objektin kenttien käsittelyä varten tehtyjä turvallisia apufunktioita. Jaettu erittäin iso "Scene" moduuli osiin "Camera", "Math", "Physics", "PlayerController" ja "SceneLogic". Näiden moduulien yhteiset tyypit piti siirtää "SceneTypes" moduuliin, koska Nim ei tue syklisiä importteja. Siistitty kamerakoodia ja siirretty pelin simulaatiosilmukan logiikkaa päämoduulista "SceneLogic" moduuliin. Selvitetty automaattisen formatointityökälyn "nph" käyttöä. En saanut sitä vielä toimimaan kunnolla, koska se formatoi myös automaattisesti generoitua OpenGL binding Nim kirjastoa.

- 4.6.2026 6h Lisätty automaattinen formatointityökalu projektiin ja formatoitu koodi sillä. Siistitty koodia siirtämällä isoista moduuleista koodia uusiin moduuleihin. Valmisteltu input järjestelmää, joka osaa tallentaa ja toistaa uudelleen pelaajan syötteet.

- 5.6.2026 4h Viimeistelty input järjestelmä ja pelaamisesta uusintojen tallentaminen sekä toistaminen. Siirretty pelin näppäimistön käsittely input järjestelmälle. Hiiren syötteet on vielä tässä versiossa input järjestelmän ulkopuolella.

- 7.6.2026 2.5h Lisätty hiiren syötteet osaksi input järjestelmää. Nyt uusinnat toimii melko hyvin. Siistitty input järjestelmän koodia.

- 8.6.2026 5h Korjattu replay järjestelmän bugeja ja tehty siitä deterministisempi tallentamalla deltaTime ja monoTime (pelin simulaationopeus ja aika pelin avauksesta). Siistitty hiiren käsittelyyn ja input järjestelmään liittyvää koodia. Lisätty dokumentaatiorunko kurssin palautusta varten.

- 9.6.2026 4h Siistitty koodia. Korjattu replay järjestelmän bugeja. Nyt replay järjestelmä on riittävän tarkka, että pelaaja on täsmälleen samassa sijainnissa pelaamisen lopuksi ja tästä pelauksesta tallennetun uusinnan loputtua. Replay järjestelmä oli yllättävän vaikea saada toimimaan kunnolla, koska lohkoittain tallennettujen binääritiedostojen käsittely osoittautui melko vaikeaksi. Toisaalta binäärinä tallennetut uusinnat ovat melko pieniä siihen nähden, että uusinnoissa ei käytetä pakkausta ja niihin tallennetaan kaikki pelaajan syötteet 60 kertaa sekunnissa. Uusinta vie noin 570 kilotavua minuutin pelaamista varten.

- 10.6.2026 7h Siistitty repläy järjestelmän ja pelin koodia. Siirretty simulaatiologiikka ja pelin tilan hallinta kokonaan erilliseen moduuliin GameLogic. Nyt on mahdollista kirjoittaa pelin testaaja, joka pyörittää samaa logiikkaa kuin itse peli.

- 11.6.2026 4h Lisätty replay järjestelmään pelin konfiguraation tallennus. Nyt uusinta ottaa huomioon esim. kameran kääntönopeuden, jonka pelaaja asetti käynnistäessään pelin. Siistitty koodia ja yhdenmukaistettu funktioiden nimeämistä.

- 12.6.2026 4h Lisätty pelin end-to-end testausjärjestelmä, joka luo uusinnasta testin. Testiin tallennetaan pelin alku- ja lopputila sekä uusinnan nimi josta testi on luotu. Testtin suorittaminen lataa pelin alkutilan ja suorittaa pelin simulaation uusinnan syötteillä loppuun asti. Sen jälkeen testi tarkistaa, että simulaation jälkeen pelin tila vastaa tallennettua lopputilaa. Näin voidaan tarkistaa, onko pelin toiminta muuttunut yhtään testin luontihetkestä.

- 13.6.2026 4h Luotu skripti, joka pakkaa pelin ja kaiken olennaisen datan release buildia varten .tar.xz tiedostoon. Muutettu projektia niin, että pakattu release versio toimii suoraan Cubbli koneilla. Tätä varten piti mm. poistaa kovakoodattuja polkuja ja muuttaa shaderien latausta niin, että se ei vaadi Slang shader compileria.

- 14.6.-15.6. 10h Korjattu Cubblia varten tehtyjen shader compilation muutosten aiheuttamia bugeja. Paranneltu release paketin luontia. Lisätty 3D ympäristöjen luontiin SceneBuilder kirjasto. Lisätty unittest2 testauskirjastoa käyttävä testi, joka ajaa kaikki replay järjestelmään pohjautuvat testit. Kirjotettu paljon dokumentaatiota.