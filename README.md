Universal Dictionary of Concepts
================================
Common U++ UNL dictionary
-------------------------
This is a multilingual pivot dictionary designed for various computer linguistic applications. An artificial language UNL (Universal Networking Language) http://www.undl.org is used as a neutral pivot to link words of different natural languages with each other. The basic units of the dictionary are "UNL concepts" or "Interlingual lexemes", which are usually equivalent to individual word senses. They are uniquely labeled with UNL "Universal Words" (UW). Each UW in the dictionary may be linked to one or several words in different natural languages (NL). 

For example, in order to translate a word into another human language we should 1) get the list of its possible senses 2) choose one or more senses, that we are interested in, and get the corresponding UWs  3) check what words may be used to represent this sense in the target language.

For example, the English word *milk* has several senses: 
- *milk(icl>dairy_product>thing)*  "A white nutritious liquid secreted by mammals.." [semantic class "Milk"] 
- *milk(icl>foodstuff>thing)* "Any of several nutritive milklike liquids" [semantic class "Beverage"]
- *milk(iof>river>thing)* "A tributary of the Missouri river" [instance of the semantic class "River"]

Your appication will know that the first two can be translated into Russian as *молоко*, French as *lait*, Malay as *susu*, etc., but in the last case it should be left as is or transliterated, e.g. as *Милк* in Russian.

The dictionary consists of several volumes, one for each language/orthography variant/dialect. An additional volume holds links between UWs.
Each NL volume contains links between words of some natural language and UNL UWs. It may also provide links to the dictionaries of computer systems used to convert NL text to UNL or deconvert UNL back to the NL. The idea is to enable continuous automated dictionary data exchange and synchronization between different systems that support UNL for the sake of interoperability. The UNL volume provides definitions of the UWs, and links to other semantic resources.

**This repository provides only data.** There is no dedicated GUI shell to view or edit it here. To browse the data locally you can get xdxf formatted version in data/xdxf, which is compatible with several dictionary shells.


License:
--------
This data as a whole is available under the terms of GNU General Public License v3 or later and Creative Commons License (CC-BY-SA). It means that you are welcome to download, view, use, convert to other formats, modify and distribute the data. Commercial use and distribution in opensource GPL projects is permitted by GPL. Other terms may be negotiated with the authors and members of the U++ Consortium: http://www.unl.fi.upm.es/consorcio/index.php?estado=publicaciones&idioma=ingles&grupo=Publico
IITP RAS (Moscow), GETALP (Grenoble), UPM (Madrid), IIT (Mumbai).

Data from external resources may also fall under futher licenses, notably WOLF is under CeCILL-C. The NL volumes may include bindings of the NL words to the dictionaries of linguistic processors, such as ETAP-3 (Russian, English) and Ariane (French). These systems and their dictionaries are not covered or restricted in any way by the licenses above.



Authors:
--------
- Viacheslav Dikonov - Russian and initial versions of the French, Malay and Vietnamese volumes.
- Spanish UNL center at UPM (Madrid) - Initial set of UWs generated automatically from Princeton Wordnet 2.1.
- French UNL center "Study Group for Machine Translation and Automated Processing of Languages and Speech" at the Laboratory of Informatics (LIG) in Grenoble (UMR CNRS/INPG/UJF 5217) - French dictionary, dBPedia conversion, terminology and support in making the initial version of the Russian volume.
- Center for Indian Language Technology (CFILT) in Mumbai - Hindi dictionary

Contributors:
------------
- Dr. Enya Kong Tang - Malay data
- Dr. Hung Vo Trung - Vietnamese data
- Mathieu Mangeot - Pivax system


Other resources used:
---------------------
- Princeton Wordnet 2.1, 3.0
- WOLF French Wordnet (part of the French volume)
- GPL subset of a Spanish Wordnet translation
- FEV dictionary for Vietnamese
- SUMO
- DBPedia


Related links:
--------------
**Online demos of UNL enabled MT systems:**
- Russian/English ⇄ UNL converter and deconverter is available at http://www.unl.ru.
- A UNL → Spanish deconverter is found at http://www.unl.fi.upm.es/english/lg_test.htm

**Other UNL dictionaries:**
- The UNL Development Center (UNDC) dictionary: http://www.undl.org/unlexp/
- UNLArium UNLdic http://www.unlweb.net/unlarium/

