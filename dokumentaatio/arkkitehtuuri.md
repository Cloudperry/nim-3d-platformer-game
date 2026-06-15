# Arkkitehtuurikuvaus

## Rakenne

![Moduulien rakenne](./kuvat/peli-moduulien-riippuvuudet.drawio.svg)

- Pelin päämoduuli Game sisältää pelin ikkunan luonnin, renderöinnin sekä syötteiden lukemisen pelaajalta
- Moduuli GameLogic sisältää pelin tilan hallinnan, kuten pelin tilan sisältävän objektin alustuksen/siivoamisen ja päivittämisen pelin simulaation avulla. Tämä moduuli myös määrittää pelin "toiminnot", kuten hyppää ja kävele eteenpäin.
- Moduuli Input toteuttaa järjestelmän, jolla syötteitä (kuten nappi) voidaan sitoa toimintoihin (kuten hyppiminen). Olennaisena osana input järjestelmää on replay järjestelmä, joka pystyy tallentamaan syötteet binäärinä varastoituun tiedostoon. Uusintoja käytetään myös testaamiseen.
- Moduuli Containers sisältää vain CircularBuffer -tietorakenteen, joka on staattisen kokoinen lista johon voi "työntää" uusia esineitä. Listaan työntäminen alkaa ylikirjoittamaan edellisiä esineitä alusta, kun mennään listan alun yli.
- Moduuli TestScenes sisältää yhden koodissa määritellyn testitason, joka on pelin ainut taso
- Moduuli SceneBuilder sisältää kirjaston, jolla voi luoda 3D-ympäristön yksinkertaisista muodoista, kuten pallo ja laatikko
- Moduuli SceneLogic sisältää 3D-ympäristön ja sen olioiden (Entity) käsittelyyn liittyvää logiikkaa
- Moduuli PlayerController sisältää pelaajan liikkeeseen ja fysiikkasimulaatioon liittyvän logiikan
- Moduuli Physics sisältää törmäysten ratkaisuun liittyvää matematiikkaa ja apufunktioita
- Moduuli CameraController sisältää kameran kääntämiseen ja renderöintiin liittyvän matematiikan sekä lentävän kameran logiikan
- Moduuli SceneTypes sisältää useiden 3D-ympäristöön ja pelaajaan liittyvien moduulien tarvitsemia itse määriteltyjä tyyppejä (objekteja). Lisäksi se toteuttaa niiden käyttöön liittyviä operaattoreita (vertailu, kenttien turvallinen lukeminen).
- Moduuli GlUtils sisältää itse tehdyn OpenGL 4(.6) abstraktion, jota peli käyttää renderöintiin

## Käyttöliittymä

Käyttöliittymä koostuu kahdesta eri osasta:
- Pelin ikkuna, jossa näkyy pelin 3D ympäristö
- Terminaalin lokitusnäkymä, joka näyttää tietoa pelin suorituskyvystä alimmalla rivillä ja lokeja sen yläpuolella (lokeja käytetty kehityksen aikana, mutta tällä hetkellä ei lokitusta)

## Sovelluslogiikka (pelin simulaatio)

- Pelin simulaation ytimessä on Scene objekti, joka sisältää mm. pelin ympäristön 3D mallit ja kaikki ympäristössä olevat oliot kuten pelaajan ja "törmäyslaatikot", joiden avulla pelaajan käveleminen ja hyppiminen tasanteilla toimii.
- Olioita esittää Entity objekti, joka sisältää eri komponentteja. Komponentit toteuttavat eri toiminnallisuuksia, kuten kameran, törmäyslaatikon sekä pelaajan. Yksi Entity voi sisältää useita komponentteja. Esim. pelaaja koostuu kamerasta, törmäyslaatikosta sekä pelaajan liikettä hallitsevasta komponentista PlayerController. Oliot on toteutettu yleisesti käytetyllä ns. "Megastruct" rakenteella, jossa yksi objekti sisältää kaikkien pelin eri olioiden datan. Kenttien luku on tehty turvalliseksi estämällä lukemasta kyseiseen olioon epäolennaista dataa. Esim. pelkästä kamerasta ei voi lukea törmäyslaatikon dataa. Kaikkien olioiden esittäminen yhtenä objektina helpottaisi eri skriptattavien esineiden vuorovaikutusta keskenään.
- Tällä hetkellä pelin simulaatio pyörii pelaajan näytön virkistystaajuudella ja mukautuu siihen, kuinka nopeasti pelaajan kone kykenee renderöimaan. Toisaalta luotettavamman simulaation yleensä tuottaa simuloida aina samalla tahdilla (esim. 60 kertaa sekunissa) eikä mukautuminen koneen nopeuteen.

## Sovelluslogiikka (input järjestelmä)
- Input järjestelmä on tärkeä osa peliä
- Sen avulla peli määrittää eri toiminnot, jotka ovat pelaajalta syötettä ottavia funktioita. Toiminnolla on tietty syötteen tyyppi (esim. Vec2f eli kahden floatin vektori).
- Toiminntoi sidotaan tiettyihin nappeihin, ja järjestelmä on tehty niin, että niitä olisi mahdollista vaihtaa lennossa esim. asetuksista pelin sisällä.
- Input järjestelmä toteuttaa myös replay järjestelmän, joka tallentaa pelin alkutilan ja pelaajan syötteet sekä pelin simulaationopeuteen liittyvät arvot
- Tallennettujen syötteiden avulla voidaan suorittaa täsmälleen sama pelisimulaatio uusiksi ja näyttää uusinta tallennetusta pelauksesta
- Lisäksi replay järjestelmän avulla on toteutettu end-to-end testit pelisimulaatiota varten
- Testit suorittaa simulaation tallennetun uusinnan perusteella uudestaan pelin uusimmalla versiolla. Jos simulaation lopuksi pelin tila vastaa testiin tallennettua tilaa, voidaan varmistua siitä, että pelisimulaation käyttäytyminen ei ole muuttunut merkittävästi. 
- Testaukseen olisi mahdollista lisätä myös pelin tilan tarkistuksia simulaation keskellä, joka voisi parantaa testien tarkkuutta. Toisaalta hyppelypelissä pelimekaniikkojen tai simulaation muuttuminen lähes aina tarkoittaisi sitä, että samoilla syötteillä päädyttäisiin eri lopputilaan. 

# Tietojen tallennus
- Peli tallentaa uusintoja ja testidataa binäärinä Nim kirjaston avulla, joka käytännössä vain kopioi muistin sisällöt yhteen puskuriin tai tiedostoon
- Tämä on lähes välttämätöntä suuren datamäärän takia, koska peli simuloi 60 kertaa sekunissa ja prosessoi monien nappien sekä hiiren syötteitä joka simulaatioaskeleella
- Toisaalta binääritallennuksen takia tiedostojen taaksepäin yhteensopivuus on melko huono. Uusien kenttien lisääminen objekteihin olisi todella helppo tehdä taaksepäin yhteensopivaksi, mutta monimutkaisempia objektien muutoksia varten tarvittaisiin melko paljon koodia.
- Uusintojen formaattia ei ole juuri mitään syytä vaihtaa, joten uusintojen osalta taaksepäin yhteensopivuus ei ole iso ongelma
- Yksi uusinta koostuu tiedostoista \<nimi\>.ActionNames.replay (pelaajan syötteet) ja \<nimi\>.Config.bin (pelin käynnistysasetukset) 

<!-- TODO: Tähän kannattaisi lisätä ainakin rakenteeseen jääneet heikkoudet ja olisi hyvä lisätä jotain tärkeimmistä pelimekaniikoista ja niiden soveltamisesta (esim. seinähypyn resetit hyppimällä eri seinään jne.) -->