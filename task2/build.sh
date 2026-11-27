cd puml
plantuml -tsvg *.puml
cp *.svg ../diagrams
cd ..
typst compile main.typ
mv main.pdf task2.pdf
