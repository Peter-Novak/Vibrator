/*
***********************************************************************************************************************************************************
*                                                                                                                                                         *
* Vibrator DX-UL1975KX-01/165.mq4,                                                                                                                           *
*                                                                                                                                                         *
* Copyright october 2014, Peter Novak ml.                                                                                                            *
***********************************************************************************************************************************************************
*/
/* Zgodovina verzij ---------------------------------------------------------------------------------------------------------------------------------------
09.10.2014 Verzija UL1975KX-01/165 
Prva verzija algoritma - proof of concept
--------------------------------------------------------------------------------------------------------------------------------------------------------*/



#property copyright "Peter Novak ml., M.Sc."
#property link      "http://www.marlin.si"



/* VibratorDX UL1975KX-01/165
	
Algoritem deluje takole:
	
	Faza I: INICIALIZACIJA
	-------------------------------------------------------------------------------------------------------------------------------------------------------------- 
	Odpre eno pozicijo BUY in eno pozicijo SELL po tržni ceni. Obe poziciji imata stop loss in take profit nastavljeni enako:
	
		- stop loss: steviloRavni*vmesnaRazdalja,
		- take profit: vmesnaRazdalja 

  Na razdalji vmesnaRazdalja nad odprtima pozicijama odpremo en BUY in en SELL order, stop loss in take profit nastavimo enako.
  Na razdalji vmesnaRazdalja pod odprtima pozicijama odpremo en BUY in en SELL order, stop loss in take profit nastavimo enako.


	Faza II: SPREMLJANJE
	--------------------------------------------------------------------------------------------------------------------------------------------------------------
Če je dosežen take profit trenutne BUY pozicije, potem:
    - odpremo nadomestni vstopni ukaz z enakimi karakteristikami.
    - trenutna BUY pozicija je odprta pozicija nad trenutno zaprto
    - odpremo nov par vstopnih ukazov na razdalji vmesnaRazdalja nad trenutno BUY pozicijo
Če je dosežen take profit trenutne SELL pozicije, potem:
    - odpremo nadomestni vstopni ukaz z enakimi karakteristikami.
    - trenutna SELL pozicija je odprta pozicija nad trenutno zaprto
    - odpremo nov par vstopnih ukazov na razdalji vmesnaRazdalja pod trenutno SELL pozicijo
*/



// Vhodni parametri ---------------------------------------------------------------------------------------------------------------------------------------
extern string imeDatoteke;       // Identifikator datoteke kamor shranjujemo stanje
extern int    maxSteviloRavni;   // Največje število ravni
extern double vmesnaRazdalja;    // Razdalja med ravnemi
extern double tpVrednost;        // Profitni cilj (EUR)
extern int    restart;           // Restart 1 - DA, 0 - NE
extern double velikostPozicij;   // Velikost pozicij (v lotih)
extern int    zaustavitev;       // 1 - DA, 0 - NE




// Globalne konstante -------------------------------------------------------------------------------------------------------------------------------------
#define MAX_POZ 500 // največje možno število odprtih pozicij v eno smer
#define S0      10
#define S4      40
#define NAPAKA  -1
#define USPEH    1



// Globalne spremenljivke ---------------------------------------------------------------------------------------------------------------------------------
double aktualnaTPVrednost;   // aktualni profitni cilj (tpVrednost)
int    dan;                  // številka dneva
double izkupicekAlgoritma;   // trenutni izkupiček algoritma
int    kazTrenutnaProdajna;  // kazalec na trenutno prodajno pozicijo
int    kazTrenutnaNakupna;   // kazalec na trenutno nakupno pozicijo
int    kazZgornjiRob;        // kazalec na zgornji rob
int    kazSpodnjiRob;        // kazalec na spodnji rob
int    nakPozicije[MAX_POZ]; // polje id-jev nakupnih pozicij
int    proPozicije[MAX_POZ]; // polje id-jev prodajnih pozicij
int    stanje;               // trenutno stanje DKA
int    steviloPozicij;       // trenutno število pozicij
double slRazdalja;           // standardna stop loss razdalja
double tpRazdalja;           // standardna take profit razdalja
double vrednostPozicij;      // vrednost vseh trenutno odprtih pozicij



/*
***********************************************************************************************************************************************************
*                                                                                                                                                         *
* GLAVNI PROGRAM in obvezne funkcije: init, deinit, start                                                                                                 *
*                                                                                                                                                         *
***********************************************************************************************************************************************************
*/



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: deinit  

Funkcionalnost:
---------------
Sistem jo pokliče ob zaustavitvi. NS001 je ne uporablja.

Zaloga vrednosti:
-----------------
/

Vhodni parametri:
-----------------
/

Implementacija: 
--------------- */   
int deinit()
{
  return( USPEH );
} // deinit 



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: init  

Funkcionalnost:
---------------
Sistem jo pokliče ob zagonu. V njej nastavimo začetno stanje avtomata, začetni izkupiček algoritma in izpišemo pozdravno sporočilo.

Zaloga vrednosti:
-----------------
/

Vhodni parametri:
-----------------
/

Implementacija: 
--------------- */
int init()
{
  Print( "****************************************************************************************************************" );
  Print( "* Welcome on behalf of VibratorDX UL1975KX-01/165 Let's f*** and **** the biatch!                                             *" );
  Print( "****************************************************************************************************************" );
 
  double cena; 
  double cenaRavni;
  
  // inicializacija vseh globalnih spremenljivk
  aktualnaTPVrednost  = tpVrednost;
  dan                 = DayOfYear();
  izkupicekAlgoritma  = 0;
  kazTrenutnaNakupna  = MAXPOZ / 2;
  kazTrenutnaProdajna = kazTrenutnaNakupna;
  kazZgornjiRob       = KazTrenutnaNakupna;
  kazSpodnjiRob       = kazTrenutnaNakupna;
  vrednostPozicij     = 0;
  slRazdalja          = maxSteviloRavni * vmesnaRazdalja;
  tpRazdalja          = vmesnaRazdalja;
  
	
	// če smo algoritem restartali, potem inicializiramo algoritem na podlagi zapisa v datoteki. Po restartu postavimo restart na 0.
	if( restart == 1 )
	{ 
	   stanje = PreberiStanje( imeDatoteke );
	   if( stanje == NAPAKA ) 
	   { Print( "Inicializacija ni bila uspešna, algoritem prekinjen - prehod v končno stanje S4." ); stanje = S4; return( S4 ); }
	   else
	   { restart = 0; IzbrisiDatoteko( imeDatoteke ); ShraniStanje( imeDatoteke ); return( stanje ); }
	}
	
	
	// inicializacija vrednosti polj pozicij
	for( int j = 0; j < MAX_POZ; j++ )
	{
	   nakPozicije[ j ] = 0;
	   proPozicije[ j ] = 0;
	}
	
	// odpiranje začetnega nabora pozicij
	nakPozicije[ kazTrenutnaNakupna  ] = OdpriPozicijo( OP_BUY,  slRazdalja, tpRazdalja  ); 
	proPozicije[ kazTrenutnaProdajna ] = OdpriPozicijo( OP_SELL, slRazdalja, tpRazdalja  );
	
	// ugotovim na kateri ceni je trenutna (začetna raven)
	cena      = CenaOdprtja( nakPozicije[ kazTrenutnaNakupna ] );
	
	// odpremo še par vstopnih ukazov eno raven višje
	cenaRavni = cena + vmesnaRazdalja;
	nakPozicije[ kazTrenutnaNakupna + 1 ] = OdpriDodatniUkaz( OP_BUY_STOP, 
		cenaRavni, 
		cenaRavni - slRazdalja, 
		cenaRavni + vmesnaRazdalja );
	proPozicije[ kazTrenutnaProdajna + 1 ] = OdpriDodatniUkaz( OP_SELL_LIMIT,
		cenaRavni,
		cenaRavni + slRazdalja,
		cenaRavni - vmesnaRazdalja );
		
	// ...ter par vstopnih ukazov eno raven nižje
	cenaRavni = cena - vmesnaRazdalja;
	nakPozicije[ kazTrenutnaNakupna - 1 ] = OdpriDodatniUkaz( OP_BUY_LIMIT, 
		cenaRavni, 
		cenaRavni - slRazdalja, 
		cenaRavni + vmesnaRazdalja );
	proPozicije[ kazTrenutnaProdajna - 1 ] = OdpriDodatniUkaz( OP_SELL_STOP,
		cenaRavni,
		cenaRavni + slRazdalja,
		cenaRavni - vmesnaRazdalja );
		
        // PN: opozorilo če pride pri odpiranju pozicije do napake - nadomestimo z bullet proof error handlingom, če bodo testi pokazali profitabilnost
	if( ( nakPozicije[ kazTrenutnaNakupna ] == NAPAKA ) || ( proPozicije[ kazTrenutnaProdajna ] == NAPAKA ) ) { Print("init: NAPAKA pri odpiranju pozicije ", i ); }

	IzbrisiDatoteko( imeDatoteke ); 
	ShraniStanje( imeDatoteke );
	return( S0 );
} // init



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: start  

Funkcionalnost:
---------------
Glavna funkcija, ki upravlja celoten algoritem - sistem jo pokliče ob vsakem ticku. 

Zaloga vrednosti:
-----------------
/

Vhodni parametri:
-----------------
/

Implementacija: 
--------------- */
int start()
{
  int trenutnoStanje; // zabeležimo za ugotavljanje spremebe stanja
 
  trenutnoStanje = stanje;
  switch( stanje )
  {
    case S0: stanje = StanjeS0(); break;
    case S4: stanje = StanjeS4(); break;
    default:
      Print( "NS001::start::OPOZORILO: Stanje ", stanje, " ni veljavno stanje - preveri pravilnost delovanja algoritma." );
  }

  // zabeležimo stanje algoritma, če je prišlo do prehoda med stanji
  if( trenutnoStanje != stanje ) 
  { 
    IzbrisiDatoteko( imeDatoteke ); ShraniStanje( imeDatoteke ); 
    Print( "Prehod: ", ImeStanja( trenutnoStanje ), " -----> ", ImeStanja( stanje ) ); 
  }
  
  // izpis ključnih parametrov algoritma na zaslonu
  Comment( "Izkupicek algoritma: ",       DoubleToString( izkupicekAlgoritma, 2                   ), " EUR\n", 
           "Trenutna vrednost pozicij: ", DoubleToString( vrednostPozicij,    2                   ), " EUR\n" 
           "Skupno stanje: ",             DoubleToString( vrednostPozicij + izkupicekAlgoritma, 2 ), " EUR\n",
           "Cilj: ",                      DoubleToString( aktualnaTPVrednost, 2                   ), " EUR\n"
           );
  
  return( USPEH );
} // start



/*
***********************************************************************************************************************************************************
*                                                                                                                                                         *
* POMOŽNE FUNKCIJE                                                                                                                                        *
*                                                                                                                                                         *
***********************************************************************************************************************************************************
*/



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ImeStanja( int KodaStanja )

Funkcionalnost:
---------------
Na podlagi numerične kode stanja, vrne opis stanja.  

Zaloga vrednosti:
-----------------
imena stanj

Vhodni parametri:
-----------------
KodaStanja: enolična oznaka stanja. 

Implementacija: 
--------------- */
string ImeStanja( int KodaStanja )
{
  switch( KodaStanja )
  {
    case S0: return( "S0" );
    case S4: return( "S4" );
    default: return( "NS001::ImeStanja::OPOZORILO: KodaStanja ni prepoznana. Preveri pravilnost delovanja algoritma." );
  }
} // ImeStanja



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: IzbrisiDatoteko( string ime )

Funkcionalnost:
---------------
Na podlagi imena datoteke izbrišemo datoteko, če obstaja. 

Zaloga vrednosti:
-----------------
USPEH

Vhodni parametri:
-----------------
identifikator datoteke

Implementacija: 
--------------- */
string IzbrisiDatoteko( string ime )
{
  string polnoIme = "NS001-" + ime + ".dat";
  
  if( FileIsExist( polnoIme ) == true ) { FileDelete( polnoIme ); } else { Print( "NS001:IzbrisiDatoteko: datoteka ", polnoIme, " ne obstaja." ); }
  return( USPEH );
} // IzbrisiDatoteko



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: OdpriNadomestnoPozicijo( int id )

Funkcionalnost:
---------------
Odpre buy ali sell stop entry order na enaki ceni kot jo ima podana pozicija, z enakim stop loss-om. 

Zaloga vrednosti:
-----------------
id odprte pozicije: če je bilo odpiranje pozicije uspešno;
NAPAKA: če odpiranje pozicije ni bilo uspešno; 

Vhodni parametri:
-----------------
id

Implementacija: 
--------------- */
int OdpriNadomestnoPozicijo( int id )
{
  bool Rezultat1 = false; // začasna spremenljivka za rezultat OrderSelect funkcije
  int  Rezultat2 = -1;;   // začasna spremenljivka za rezultat OrderSend funkcije
 
  // poiščemo pozicijo, ki jo nadomeščamo
  Rezultat1 = OrderSelect( id, SELECT_BY_TICKET );
  if( Rezultat1 == false ) { Print( "OdpriNadomestnoPozicijo::NAPAKA: pozicije z oznako ni: ", id ); return( NAPAKA ); }
  else 
    { 
      do 
      {
        if( OrderType() == OP_BUY )  
          { Rezultat2 = OrderSend( Symbol(), OP_BUYSTOP,  velikostPozicij, OrderOpenPrice(), 0, OrderStopLoss(), OrderTakeProfit(),  "NS001", 0, 0, Green );  }
        if( OrderType() == OP_SELL ) 
          { Rezultat2 = OrderSend( Symbol(), OP_SELLSTOP, velikostPozicij, OrderOpenPrice(), 0, OrderStopLoss(), OrderTakeProfit(),  "NS001", 0, 0, Green );  }
        if( Rezultat2 == -1 ) 
          { 
            Print( "OdpriNadomestnoPozicijo::NAPAKA: neuspešno odpiranje nadomestne pozicije. Ponoven poskus čez 30s...", id );
            Sleep( 30000 );
            RefreshRates();
          }
      } 
      while( Rezultat2 < 0 );
    }
    return( Rezultat2 );
} // OdpriNadomestnoPozicijo



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: OdpriDodatniUkaz( int tip, double cena, double sl, double tp )

Funkcionalnost:
---------------
Odpre buy ali sell order podanega tipa s podanima stop loss-om in take profitom

Zaloga vrednosti:
-----------------
id odprte pozicije: če je bilo odpiranje pozicije uspešno;
NAPAKA: če odpiranje pozicije ni bilo uspešno; 

Vhodni parametri:
-----------------
id

Implementacija: 
--------------- */
int OdpriDodatniUkaz( int tip, double cena, double sl, double tp )
{
  int    Rezultat2; // začasna spremenljivka za rezultat OrderSend funkcije
  double stop;
  double profit;
  
  if( ( tip == OP_BUYLIMIT) || ( tip == OP_BUYSTOP ) ) { stop = cena - sl; profit = cena + tp;} else { stop = cena + sl; profit = cena - tp; }
  do
   {
     Rezultat2 = OrderSend( Symbol(), tip,  velikostPozicij, cena, 0, stop, profit,  "DX", 0, 0, Green );
     if( Rezultat2 == -1 ) 
          { 
            Print( "OdpriDodatniUkaz::NAPAKA: neuspešno odpiranje dodatne pozicije. Ponoven poskus čez 30s..." ); 
            Sleep( 30000 );
            RefreshRates();
          }
    }
   while( Rezultat2 == -1 );
   return( Rezultat2 );
} // OdpriDodatniUkaz



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: OdpriPozicijo( int Smer, double sl, double tp )

Funkcionalnost:
---------------
Odpre pozicijo po trenutni tržni ceni v podani Smeri. Če gre za pozicijo nakup (Smer OP_BUY):
* nastavi stop loss podano razdaljo točk pod ceno odprtja;
* nastavi take profit podano razdaljo nad ceno odprtja;

Če gre za pozicijo prodaja (Smer OP_SELL):
* nastavi stop loss podano razdaljo točk nad ceno odprtja;
* nastavi take profit podano razdaljo pod ceno odprtja;

Zaloga vrednosti:
-----------------
id odprte pozicije: če je bilo odpiranje pozicije uspešno;
NAPAKA: če odpiranje pozicije ni bilo uspešno; 

Vhodni parametri:
-----------------
Smer: OP_BUY ali OP_SELL.
razdalja: razdalja

Implementacija: 
--------------- */
int OdpriPozicijo( int Smer, double sl, double tp )
{
  int Rezultat;
 
  do
    {
      if( Smer == OP_BUY ) { Rezultat = OrderSend( Symbol(), OP_BUY,  velikostPozicij, Ask, 0, Ask - sl, Ask + tp, "NS001", 0, 0, Green ); }
      else                 { Rezultat = OrderSend( Symbol(), OP_SELL, velikostPozicij, Bid, 0, Bid + sl, Bid - tp, "NS001", 0, 0, Red   ); }
      if( Rezultat == -1 ) 
        { 
          Print( "OdpriPozicijo::NAPAKA: neuspešno odpiranje dodatne pozicije. Ponoven poskus čez 30s..." ); 
          Sleep( 30000 );
          RefreshRates();
        }
    }
  while( Rezultat == -1 );
  return( Rezultat );
} // OdpriPozicijo



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: PostaviSLnaBE( int Id )

Funkcionalnost:
---------------
Funkcija poziciji z id-jem Id postavi stop loss na break even.

Zaloga vrednosti:
-----------------
USPEH: ponastavljanje uspešno
NAPAKA: ponastavljanje ni bilo uspešno

Vhodni parametri:
-----------------
Id: oznaka pozicije.

Implementacija: 
--------------- */
int PostaviSLnaBE( int Id )
{
  int  selectRezultat;
  bool modifyRezultat;

  selectRezultat = OrderSelect( Id, SELECT_BY_TICKET );
  if( selectRezultat == false ) 
    { Print( "NS001::PostaviSLnaBE::OPOZORILO: Pozicije ", Id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( false ); }

  modifyRezultat = OrderModify( Id, OrderOpenPrice(), OrderOpenPrice(), 0, 0, clrNONE );
  if( modifyRezultat == false ) 
    { Print( "NS001::PostaviSLnaBE::OPOZORILO: Pozicije ", Id, " ni bilo mogoče ponastaviti SL na BE. Preveri ali je že ponastavljeno." ); return( NAPAKA ); } else { return( USPEH ); }
} // PostaviSLnaBE



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: PozicijaZaprta( int Id )

Funkcionalnost:
---------------
Funkcija pove ali je pozicija s podanim Id-jem zaprta ali ne. 

Zaloga vrednosti:
-----------------
true : pozicija je zaprta.
false: pozicija je odprta.

Vhodni parametri:
-----------------
Id: oznaka pozicije.

Implementacija: 
--------------- */
bool PozicijaZaprta( int Id )
{
  int Rezultat;

  Rezultat = OrderSelect( Id, SELECT_BY_TICKET );
  if( Rezultat == false ) 
    { Print( "NS001::PozicijaZaprta::OPOZORILO: Pozicije ", Id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( false ); }

  if( OrderCloseTime() == 0 ) { return( false ); } else { return( true ); }
} // PozicijaZaprta



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: PreberiStanje( string ime )

Funkcionalnost:
---------------
Funkcija prebere glavne parametre algoritma iz datoteke. Vrstni red branja je naslednji:

double vmesnaRazdalja;       // Razdalja med pozicijami
double tpVrednost;           // Profitni cilj (EUR)
double velikostPozicij;      // Velikost pozicij (v lotih)
double izkupicekAlgoritma;   // trenutni izkupiček algoritma
int    kazTrenutnaProdajna;  // kazalec na naslednjo odprto prodajno pozicijo
int    kazTrenutnaNakupna;   // kazalec na naslednjo odprto nakupno pozicijo
int    stanje;               // trenutno stanje DKA
int    nakPozicije[MAX_POZ]; // polje id-jev nakupnih pozicij
int    proPozicije[MAX_POZ]; // polje id-jev prodajnih pozicij



Zaloga vrednosti:
-----------------
USPEH  - branje datoteke je bilo uspešno
NAPAKA - branje datoteke ni bilo uspešno

Vhodni parametri:
-----------------
Ime datoteke.

Implementacija: 
--------------- */
int PreberiStanje( string ime )
{
  int    rocajDatoteke;
  string polnoIme;
  string spisekPozicij;

  polnoIme      = "VibratorDX-" + ime + ".dat";
  
  // odpremo datoteko
  ResetLastError();
  rocajDatoteke = FileOpen( polnoIme, FILE_READ|FILE_BIN );
  
  if( rocajDatoteke != INVALID_HANDLE)
  {
    Print( "Branje stanja algoritma iz datoteke ", polnoIme, ": " );
    Print( "----------------------------------------" );
    vmesnaRazdalja       = FileReadDouble ( rocajDatoteke, DOUBLE_VALUE );
    Print( "Razdalja med pozicijami [vmesnaRazdalja]: ",                vmesnaRazdalja );
    tpVrednost         = FileReadDouble ( rocajDatoteke, DOUBLE_VALUE );
    Print( "Profitni cilj (EUR) [tpVrednost]: ",                            tpVrednost );
    velikostPozicij    = FileReadDouble ( rocajDatoteke, DOUBLE_VALUE );
    Print( "Velikost pozicij (v lotih) [velikostPozicij]: ",           velikostPozicij );
    izkupicekAlgoritma = FileReadDouble ( rocajDatoteke, DOUBLE_VALUE );
    Print( "Trenutni izkupiček algoritma [izkupicekAlgoritma]: ",   izkupicekAlgoritma );
    kazTrenutnaProdajna  = FileReadInteger( rocajDatoteke, INT_VALUE    );
    Print( "Kazalec na trenutno prodajno [kazTrenutnaProdajna]: ", kazTrenutnaProdajna );
    kazTrenutnaNakupna   = FileReadInteger( rocajDatoteke, INT_VALUE    );
    Print( "Kazalec na trenutno nakupno [kazTrenutnaNakupna]: ",    kazTrenutnaNakupna );
    stanje             = FileReadInteger( rocajDatoteke, INT_VALUE    );
    Print( "Stanje algoritma [stanje]: ",                                     stanje );

    // polji nakupnih in prodajnih pozicij
    spisekPozicij = "Nakupne pozicije: ";
    for( int i = 0; i < MAX_POZ; i++ )
    {
      nakPozicije[ i ] = FileReadInteger( rocajDatoteke, INT_VALUE ); 
      if( nakPozicije[ i ] != 0 ) { spisekPozicij = spisekPozicij + IntegerToString( nakPozicije[ i ] ) + ", "; }
    }
    Print( StringSubstr( spisekPozicij, 0, StringLen( spisekPozicij ) - 2 ) );
    
    spisekPozicij = "Prodajne pozicije: ";
    for( int j = 0; j < MAX_POZ; j++ )
    {
      proPozicije[ j ] = FileReadInteger( rocajDatoteke, INT_VALUE ); 
      if( proPozicije[ j ] != 0 ) { spisekPozicij = spisekPozicij + IntegerToString( proPozicije[ j ] ) + ", "; }
    }
    Print( StringSubstr( spisekPozicij, 0, StringLen( spisekPozicij ) - 2 ) );
    
    FileClose( rocajDatoteke );
    return( stanje );
  }
  else 
  { 
    PrintFormat( "Napaka pri odpiranju datoteke: %s. Koda napake = %d", polnoIme, GetLastError() );
    return( NAPAKA ); 
  } 
} // PreberiStanje



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ShraniStanje( string ime )

Funkcionalnost:
---------------
Funkcija shrani vse glavne parametre algoritma v datoteko. Vrstni red shranjevanja stanja je naslednji:

double vmesnaRazdalja;       // Razdalja med pozicijami
double tpVrednost;           // Profitni cilj (EUR)
double velikostPozicij;      // Velikost pozicij (v lotih)
double izkupicekAlgoritma;   // trenutni izkupiček algoritma
int    kazTrenutnaProdajna;  // kazalec na naslednjo odprto prodajno pozicijo
int    kazTrenutnaNakupna;   // kazalec na naslednjo odprto nakupno pozicijo
int    stanje;               // trenutno stanje DKA
int    nakPozicije[MAX_POZ]; // polje id-jev nakupnih pozicij
int    proPozicije[MAX_POZ]; // polje id-jev prodajnih pozicij



Zaloga vrednosti:
-----------------
USPEH  - odpiranje datoteke je bilo uspešno
NAPAKA - odpiranje datoteke ni bilo uspešno

Vhodni parametri:
-----------------
Ime datoteke.

Implementacija: 
--------------- */
int ShraniStanje( string ime )
{
  int    rocajDatoteke;
  int    count;
  string polnoIme;
  string spisekPozicij;
  string vrsticaStanja1;
  string vrsticaStanja2;
  string vrsticaStanja3;

  polnoIme      = "VibratorDX-" + ime + ".dat";
  rocajDatoteke = FileOpen( polnoIme, FILE_WRITE|FILE_BIN );
  
  if( rocajDatoteke != INVALID_HANDLE)
  {
    Print( "Zapisovanje stanja algoritma v datoteko ", polnoIme, ": -------------------------------------------------------------------------" );
    vrsticaStanja1 = vrsticaStanja1 + "Razdalja med pozicijami [vmesnaRazdalja]: " + DoubleToString( vmesnaRazdalja, 5 ) + " \\ ";
    FileWriteDouble ( rocajDatoteke,                                    vmesnaRazdalja );
    Print( "Profitni cilj (EUR) [tpVrednost]: ", DoubleToString( tpVrednost, 2 ), " EUR" );
    FileWriteDouble ( rocajDatoteke,                                      tpVrednost );
    vrsticaStanja2 = "Velikost pozicij (v lotih) [velikostPozicij]: " + DoubleToString( velikostPozicij, 2 ) + " \\ ";
    FileWriteDouble ( rocajDatoteke,                                 velikostPozicij );
    Print( "Trenutni izkupiček algoritma [izkupicekAlgoritma]: ", DoubleToString( izkupicekAlgoritma, 2 ), " EUR" );
    FileWriteDouble ( rocajDatoteke,                              izkupicekAlgoritma );
    vrsticaStanja2 = vrsticaStanja2 + "Kazalec na odprto prodajno [kazTrenutnaProdajna]: " + IntegerToString( kazTrenutnaProdajna ) + " \\ ";
    FileWriteInteger( rocajDatoteke,                               kazTrenutnaProdajna );
    vrsticaStanja2 = vrsticaStanja2 + "Kazalec na odprto nakupno [kazTrenutnaNakupna]: " + IntegerToString( kazTrenutnaNakupna ) + " \\ ";
    FileWriteInteger( rocajDatoteke,                                kazTrenutnaNakupna );
    vrsticaStanja3 = "Stanje algoritma [stanje]: " + ImeStanja( stanje ) + " \\ ";
    FileWriteInteger( rocajDatoteke,                                          stanje );

    Print( vrsticaStanja1 );
    Print( vrsticaStanja2 );
    Print( vrsticaStanja3 );
    
    // polji nakupnih in prodajnih pozicij
    count = 4;
    spisekPozicij = "Nakupne pozicije: ";
    for( int i = 0; i < MAX_POZ; i++ )
    {
      if( nakPozicije[ i ] != 0 ) 
      { 
        spisekPozicij = spisekPozicij + IntegerToString( nakPozicije[ i ] ) + ", ";
        count--;
        if( count == 0 ) { Print( spisekPozicij ); count = 4; spisekPozicij = "                   "; }
      }
      FileWriteInteger( rocajDatoteke, nakPozicije[ i ] ); 
    }
    if( count != 4 ) { Print( StringSubstr( spisekPozicij, 0, StringLen( spisekPozicij ) - 2 ) ); }
   
    count = 4;
    spisekPozicij = "Prodajne pozicije: ";
    for( int j = 0; j < MAX_POZ; j++ )
    {
      if( proPozicije[ j ] != 0 ) 
      { 
        spisekPozicij = spisekPozicij + IntegerToString( proPozicije[ j ] ) + ", "; 
        count--;
        if( count == 0 ) { Print( spisekPozicij ); count = 4; spisekPozicij = "                   "; }
      }
      FileWriteInteger( rocajDatoteke, proPozicije[ j ] ); 
    }
    if( count != 4 ) { Print( StringSubstr( spisekPozicij, 0, StringLen( spisekPozicij ) - 2 ) ); }
    
    FileClose( rocajDatoteke );
    return( USPEH );
  }
  else { Print( "VibratorDX:ShraniStanje: Napaka pri shranjevanju stanja algoritma. Preveri pravilnost delovanja!" ); return( NAPAKA ); } 
} // ShraniStanje



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: UkazOdprt( int Id )

Funkcionalnost:
---------------
Funkcija pove ali je ukaz s podanim Id-jem odprta pozicija ali ne. 

Zaloga vrednosti:
-----------------
true : ukaz je odprta pozicija
false: ukaz ni odprta pozicija

Vhodni parametri:
-----------------
Id: oznaka pozicije.

Implementacija: 
--------------- */
bool UkazOdprt( int Id )
{
  int Rezultat;
  int tip;

  Rezultat = OrderSelect( Id, SELECT_BY_TICKET );
  if( Rezultat == false ) 
    { Print( "NS001::UkazOdprt::OPOZORILO: Pozicije ", Id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( false ); }

  tip = OrderType();
  if( ( ( tip == OP_BUY) || ( tip == OP_SELL ) ) &&
      ( OrderCloseTime() == 0 ) ) { return( true ); } else { return( false ); }
} // Ukaz odprt



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: VrednostPozicije( int Id )

Funkcionalnost:
---------------
Vrne vrednost pozicije z oznako Id.

Zaloga vrednosti:
-----------------
vrednost pozicije v EUR; 

Vhodni parametri:
-----------------
Id: oznaka pozicije.

Implementacija: 
--------------- */
double VrednostPozicije( int Id )
{
  int Rezultat;

  Rezultat = OrderSelect( Id, SELECT_BY_TICKET );
  if( Rezultat == false ) 
    { Print( "NS001::ZapriPozicijo::OPOZORILO: Pozicije ", Id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( 0 ); }
  return( OrderProfit() + OrderSwap() );
} // VrednostPozicije



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: VrednostOdprtihPozicij()

Funkcionalnost:
---------------
Vrne vsoto vrednosti vseh odprtih pozicij.

Zaloga vrednosti:
-----------------
vsota vrednosti odprtih pozicij v EUR; 

Vhodni parametri:
-----------------
/
Uporablja globalne spremenljivke.

Implementacija: 
--------------- */
double VrednostOdprtihPozicij()
{
  double vrednost = 0;

  for( int i = kazOdprtaNakupna;  i < ( steviloPozicij - 1 ); i++ ) { vrednost = vrednost + VrednostPozicije( nakPozicije[ i ] ); }
  for( int j = kazOdprtaProdajna; j < ( steviloPozicij - 1 ); j++ ) { vrednost = vrednost + VrednostPozicije( proPozicije[ j ] ); }
  vrednostPozicij = vrednost; // vrednost shranimo tudi v globalno spremenljivko, da zmanjšamo število klicev funkcije
  return( vrednost );
} // VrednostOdprtihPozicij



/*------------------------------------------------------------------------------------------------------------------------------------------------------
FUNKCIJA: ZapriPozicijo( int Id )

Funkcionalnost:
---------------
Zapre pozicijo z oznako Id po trenutni tržni ceni.

Zaloga vrednosti:
-----------------
true: če je bilo zapiranje pozicije uspešno;
false: če zapiranje pozicije ni bilo uspešno; 

Vhodni parametri:
-----------------
Id: oznaka pozicije.
Smer: vse možne variante, briše tudi ukaze

Implementacija: 
--------------- */
bool ZapriPozicijo( int Id )
{
  int Rezultat;

  Rezultat = OrderSelect( Id, SELECT_BY_TICKET );
  if( Rezultat == false ) 
    { Print( "NS001::ZapriPozicijo::OPOZORILO: Pozicije ", Id, " ni bilo mogoče najti. Preveri pravilnost delovanja algoritma." ); return( false ); }

  switch( OrderType() )
  {
    case OP_BUY:
      return( OrderClose( Id, OrderLots(), Bid, 0, Red ) );
    case OP_SELL:
      return( OrderClose( Id, OrderLots(), Ask, 0, Red ) );
    default:
      return( OrderDelete( Id ) );
  }  
} // ZapriPozicijo


/*
***********************************************************************************************************************************************************
*                                                                                                                                                         *
* FUNKCIJE DKA                                                                                                                                            *
*                                                                                                                                                         *
***********************************************************************************************************************************************************
*/



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
	Stanje 0 (S0)
	-------------
	1) če je trenutna nakupna pozicija dosegla TP, potem:
	  - prištejemo vrednost pozicije izkupičku algoritma;
	  - odpremo nadomestni ukaz;
	  - kazTrenutnaNakupna++;
	  - kazTrenutnaProdajna
	2) če je trenutna prodajna pozicija
*/
int StanjeS0()
{
  // prodajna pozicija je dosegla TP
  if( PozicijaZaprta( proPozicije[ kazTrenutnaProdajna ] ) == true ) 
    { 
      // popravimo znesek izkupička algoritma in odpremo nadomestni sell stop order
      Print("Prodajna pozicija ", kazTrenutnaProdajna, " z id-jem ", proPozicije[ kazTrenutnaProdajna ], " zaprta." );
      izkupicekAlgoritma = izkupicekAlgoritma + VrednostPozicije( proPozicije[ kazTrenutnaProdajna ] ); 
      Print("Trenutni izkupiček algoritma: ", DoubleToStr( izkupicekAlgoritma, 2 ), " EUR" );
      proPozicije[ kazTrenutnaProdajna ] = OdpriNadomestnoPozicijo( proPozicije[ kazTrenutnaProdajna ] ); 
      if( proPozicije[ kazOdprtaProdajna ] == NAPAKA ) { Print("NAPAKA:S0: Odpiranje nadomestne prodajne pozicije neuspešno." ); }
      kazTrenutnaProdajna--; 
      
      
      
      // če število pozicij še ni doseglo maksimuma, potem ga povečamo za ena in dodamo po en dodatni stop order v vsako smer
      if( steviloPozicij < maxSteviloPozicij )
        { 
          // indeks steviloPozicij - 1 vedno kaže na pozicijo z največjim stop loss-om
          proPozicije[ steviloPozicij ] = OdpriDodatniUkaz( OP_SELLSTOP, proPozicije[ steviloPozicij - 1 ] );
          nakPozicije[ steviloPozicij ] = OdpriDodatniUkaz( OP_BUYLIMIT, nakPozicije[ steviloPozicij - 1 ] );
          if( ( nakPozicije[ steviloPozicij ] == NAPAKA ) ||
              ( proPozicije[ steviloPozicij ] == NAPAKA ) ) { Print( "NAPAKA:S0: Odpiranje dodatnih pozicij neuspešno." ); }
          steviloPozicij++;
        }
      return( S1 ); 
    } 
  
  // S0 --> S2 
  // pozicije so v polju nakPozicije urejene po vrsti, če se je sprožil SL, se je sprožil na prvi odprti nakupni poziciji
  if( PozicijaZaprta( nakPozicije[ kazOdprtaNakupna ] ) == true ) 
    { 
      // popravimo znesek izkupička algoritma in odpremo nadomestni sell stop order
      Print("Nakupna pozicija ", kazOdprtaNakupna, " z id-jem ", nakPozicije[ kazOdprtaNakupna ], " zaprta - izpolnjen pogoj za prehod v smer prodaje (S2)." );
      izkupicekAlgoritma = izkupicekAlgoritma + VrednostPozicije( nakPozicije[ kazOdprtaNakupna ] ); 
      Print("Trenutni izkupiček algoritma: ", DoubleToStr( izkupicekAlgoritma, 2 ), " EUR" );
      nakPozicije[ kazOdprtaNakupna ] = OdpriNadomestnoPozicijo( nakPozicije[ kazOdprtaNakupna ] ); 
      kazOdprtaNakupna++; 
      
      // če število pozicij še ni doseglo maksimuma, potem ga povečamo za ena in dodamo po en nadomestni stop order v vsako smer
      if( steviloPozicij < maxSteviloPozicij )
        { 
          proPozicije[ steviloPozicij ] = OdpriDodatniUkaz( OP_SELLLIMIT, proPozicije[ steviloPozicij - 1 ] );
          nakPozicije[ steviloPozicij ] = OdpriDodatniUkaz( OP_BUYSTOP,   nakPozicije[ steviloPozicij - 1 ] );
          if( ( nakPozicije[ steviloPozicij ] == NAPAKA ) ||
              ( proPozicije[ steviloPozicij ] == NAPAKA ) ) { Print( "NAPAKA: Odpiranje dodatnih pozicij neuspešno." ); }
          steviloPozicij++;
        }
      return( S2 ); 
    }   
  
  return( S0 );   

} // StanjeS0



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
Stanje S1
---------
Stanje 1 (S1)
	- Invariante stanja: 
		- odprtih je več BUY pozicij kot SELL pozicij,
		- najmanj ena od SELL pozicij je dosegla stop loss, 
		- vrednost vseh odprtih pozicij + izkupiček algoritma < ciljni dobiček
	- Možni prehodi:
		- prehod v stanje S0:
			- pogoj: ko se odprejo vsi stop sell orderji in je število odprtih pozicij v obe smeri ponovno enako,
			- akcije pred prehodom: /
		- prehod v Fazo INICIALIZACIJA:
			- pogoj: vrednost vseh odprtih pozicij + izkupiček algoritma > ciljni dobiček
			- akcije pred prehodom:
				- zapremo vse odprte pozicije
*/
int StanjeS1()
{
  // prehod v fazo INICIALIZACIJA
  double vrednost = VrednostOdprtihPozicij();
  if( ( vrednost + izkupicekAlgoritma ) > aktualnaTPVrednost ) 
  { 
    for( int i = kazOdprtaNakupna + 1;  i < steviloPozicij; i++ ) { ZapriPozicijo( nakPozicije[ i ] ); } // 1 pozicijo pustimo odprto - nova noga stonoge
    for( int j = 0;                     j < steviloPozicij; j++ ) { ZapriPozicijo( proPozicije[ j ] ); } // ker moramo počistiti nadomestne sell orderje
    
    PostaviSLnaBE( nakPozicije[ kazOdprtaNakupna ] ); // nogi stonoge postavimo SL na BE
    
    Print( "Vrednost odprtih pozicij: ", DoubleToStr( vrednost, 2 ) );
    Print( "Izguba algoritma: ",      DoubleToStr( izkupicekAlgoritma, 2 ) );
    Print( "Skupni izkupiček: ", DoubleToStr( vrednost - izkupicekAlgoritma, 2 ) );
    Print( "YES! We f***** the biatch!!!! ------------------------------------------------------------------------------------------------------------" );
    // če je nastavljen parameter za zaustavitev gremo v stanje S4, sicer začnemo vse od začetka
    if( zaustavitev == 1 ) { return( S4 ); } else { return( init() ); }
  }
  
  // S1 --> S0
  if( UkazOdprt( proPozicije[ 0 ] ) == true )
  {
    Print( "Prodajne pozicije so spet vse odprte, prehod v S0" );
    kazOdprtaProdajna = 0;
    return( S0 );
  } 
  
  // če se je zaprla še kakšna od prodajnih pozicij, popravimo vrednost kazalca na naslednjo odprto pozicijo, dodamo nadomesten ukaz in popravimo izkupiček
  if( ( kazOdprtaProdajna < steviloPozicij ) && 
      (  PozicijaZaprta( proPozicije[ kazOdprtaProdajna ] ) == true ) )
  {
    Print( "Zaprta prodajna pozicija ", kazOdprtaProdajna, " z id-jem ", proPozicije[ kazOdprtaProdajna ] );
    izkupicekAlgoritma = izkupicekAlgoritma + VrednostPozicije( proPozicije[ kazOdprtaProdajna ] );
    Print( "Izkupiček algoritma: ",      DoubleToStr( izkupicekAlgoritma, 2 ) );
    proPozicije[ kazOdprtaProdajna ] = OdpriNadomestnoPozicijo( proPozicije[ kazOdprtaProdajna ] );
    kazOdprtaProdajna++;
    IzbrisiDatoteko( imeDatoteke );
    ShraniStanje   ( imeDatoteke );
  }
  return( S1 );
} // StanjeS1



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
Stanje S2
---------
	Stanje 2 (S2)
	-------------
	--> Invariante stanja: 
		o odprtih je več SELL pozicij kot BUY pozicij,
		o najmanj ena od BUY pozicij je dosegla stop loss, 
		o vrednost vseh odprtih pozicij + izkupiček algoritma < ciljni dobiček
	--> Možni prehodi:
		S2 --> S0:
			o pogoj: ko se odprejo vsi stop buy orderji in je število odprtih pozicij v obe smeri ponovno enako,
			o akcije pred prehodom: /
		ponoven zagon algoritma INICIALIZACIJA:
			o pogoj: vrednost vseh odprtih pozicij + izkupiček algoritma > ciljni dobiček
			o akcije pred prehodom:
				- zapremo vse odprte pozicije
				- zapremo vse stop orderje
*/
int StanjeS2()
{
  // prehod v fazo INICIALIZACIJA
  double vrednost = VrednostOdprtihPozicij();
  if( ( vrednost + izkupicekAlgoritma ) > aktualnaTPVrednost ) 
  { 
    for( int i = 0;                     i < steviloPozicij; i++ ) { ZapriPozicijo( nakPozicije[ i ] ); } // ker moramo počistiti nadomestne buy orderje
    for( int j = kazOdprtaProdajna + 1; j < steviloPozicij; j++ ) { ZapriPozicijo( proPozicije[ j ] ); } // eno pustimo odprto - nova noga stonoge
    
    PostaviSLnaBE( proPozicije[ kazOdprtaProdajna ] ); // nogi stonoge postavimo SL na BE
    
    Print( "Vrednost odprtih pozicij: ", DoubleToStr( vrednost, 2 ) );
    Print( "Izguba algoritma: ",      DoubleToStr( izkupicekAlgoritma, 2 ) );
    Print( "Skupni izkupiček: ", DoubleToStr( vrednost - izkupicekAlgoritma, 2 ) );
    Print( "YES! We f***** the biatch!!!! ------------------------------------------------------------------------------------------------------------" );
    // če je nastavljen parameter za zaustavitev gremo v stanje S4, sicer začnemo vse od začetka
    if( zaustavitev == 1 ) { return( S4 ); } else { return( init() ); }
  }
  
  // S2 --> S0
  if( UkazOdprt( nakPozicije[ 0 ] ) == true )
  {
    Print( "Nakupne pozicije so spet vse odprte, prehod v S0" );
    kazOdprtaNakupna = 0;
    return( S0 );
  } 
  
  // če se je zaprla še kakšna od nakupnih pozicij, popravimo vrednost kazalca na naslednjo odprto pozicijo, dodamo nadomesten ukaz in popravimo izkupiček
  if ( ( kazOdprtaNakupna < steviloPozicij ) &&
       ( PozicijaZaprta( nakPozicije[ kazOdprtaNakupna ] ) == true ) )
  {
    Print( "Zaprta nakupna pozicija ", kazOdprtaNakupna, " z id-jem ", nakPozicije[ kazOdprtaNakupna ] );
    izkupicekAlgoritma = izkupicekAlgoritma + VrednostPozicije( nakPozicije[ kazOdprtaNakupna ] );
    Print( "Izkupiček algoritma: ",      DoubleToStr( izkupicekAlgoritma, 2 ) );
    nakPozicije[ kazOdprtaNakupna ] = OdpriNadomestnoPozicijo( nakPozicije[ kazOdprtaNakupna ] );
    kazOdprtaNakupna++;
    IzbrisiDatoteko( imeDatoteke );
    ShraniStanje   ( imeDatoteke );
  }
  return( S2 );
} // StanjeS2



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
Stanje S3
---------
	Stanje 3 (S3)
	-------------
	Čakamo da nastopi čas za trgovanje
*/
int StanjeS3()
{
// če smo izven trgovalnega časa, potem gremo v stanje S3, sicer v S0 in odpremo začetni nabor pozicij
   if( TrgovalnoObdobje() == true ) { Print( "Čas je, lotimo se dela..." ); init(); return( S0 ); } else { return( S3 ); }
} // StanjeS3



/*-------------------------------------------------------------------------------------------------------------------------------------------------------
Stanje S4
---------
	Stanje 4 (S4)
	-------------
	Končno stanje - iz tega stanja ni nobenih prehodov več.
*/
int StanjeS4()
{
   return( S4 );
} // StanjeS4
