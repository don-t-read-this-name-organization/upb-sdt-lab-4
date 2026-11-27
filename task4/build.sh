cd puml
plantuml -tsvg *.puml
cp *.svg ../diagrams
cd ..
typst compile main.typ
mv main.pdf task4.pdf
