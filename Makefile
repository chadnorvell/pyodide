PYODIDE_ROOT=$(abspath .)
include Makefile.envs

FILEPACKAGER=$(PYODIDE_ROOT)/tools/file_packager.py

CPYTHONROOT=cpython
CPYTHONLIB=$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/python$(PYMINOR)

LZ4LIB=lz4/lz4-1.8.3/lib/liblz4.a
CLAPACK=CLAPACK/CLAPACK-WA/lapack_WA.bc

CC=emcc
CXX=em++
OPTFLAGS=-O3
CFLAGS=$(OPTFLAGS) -g -I$(PYTHONINCLUDE) -Wno-warn-absolute-paths
CXXFLAGS=$(CFLAGS) -std=c++14


# __ZNKSt3__220__vector_base_commonILb1EE20__throw_length_errorEv is in
# EXPORTED_FUNCTIONS to keep the C++ standard library in the core, even though
# there isn't any C++ there, for the sake of loading dynamic modules written in
# C++, such as those in matplotlib.
LDFLAGS=\
	-O3 \
	-s MODULARIZE=1 \
	$(CPYTHONROOT)/installs/python-$(PYVERSION)/lib/libpython$(PYMINOR).a \
  lz4/lz4-1.8.3/lib/liblz4.a \
  -s "BINARYEN_METHOD='native-wasm'" \
  -s TOTAL_MEMORY=1073741824 \
  -s ALLOW_MEMORY_GROWTH=1 \
	-s MAIN_MODULE=1 \
	-s EMULATED_FUNCTION_POINTERS=1 \
  -s EMULATE_FUNCTION_POINTER_CASTS=1 \
  -s EXPORTED_FUNCTIONS='["_main", "__ZNKSt3__220__vector_base_commonILb1EE20__throw_length_errorEv", "__ZNSt11logic_errorC2EPKc"]' \
  -s WASM=1 \
	-s SWAPPABLE_ASM_MODULE=1 \
	-s USE_FREETYPE=1 \
	-s USE_LIBPNG=1 \
	-std=c++14 \
  -lstdc++ \
  --memory-init-file 0 \
  -s "BINARYEN_TRAP_MODE='clamp'" \
  -s TEXTDECODER=0 \
  -s LZ4=1

SIX_ROOT=six/six-1.11.0/build/lib
SIX_LIBS=$(SIX_ROOT)/six.py

SITEPACKAGES=root/lib/python$(PYMINOR)/site-packages

all: build/pyodide.asm.js \
	build/pyodide.asm.data \
	build/pyodide.js \
	build/pyodide_dev.js \
	build/python.html \
	build/python_dev.html \
	build/matplotlib.html \
	build/matplotlib-sideload.html \
	build/renderedhtml.css \
  build/test.data \
  build/packages.json \
  build/test.html


build/pyodide.asm.js: src/main.bc src/jsimport.bc src/jsproxy.bc src/js2python.bc \
		src/pyimport.bc src/pyproxy.bc src/python2js.bc src/python2js_buffer.bc \
		src/runpython.bc src/hiwire.bc
	[ -d build ] || mkdir build
	$(CXX) -s EXPORT_NAME="'pyodide'" -o build/pyodide.asm.html $(filter %.bc,$^) \
	  $(LDFLAGS) -s FORCE_FILESYSTEM=1
	rm build/pyodide.asm.asm.js
	rm build/pyodide.asm.wasm.pre
	rm build/pyodide.asm.html


build/pyodide.asm.data: root/.built
	( \
		cd build; \
		python $(FILEPACKAGER) pyodide.asm.data --lz4 --preload ../root/lib@lib --js-output=pyodide.asm.data.js --use-preload-plugins \
  )
	uglifyjs build/pyodide.asm.data.js -o build/pyodide.asm.data.js


build/pyodide_dev.js: src/pyodide.js
	cp $< $@
	sed -i -e "s#{{DEPLOY}}##g" $@


build/pyodide.js: src/pyodide.js
	cp $< $@
	sed -i -e 's#{{DEPLOY}}#https://iodide.io/pyodide-demo/#g' $@


build/python.html: src/python.html
	cp $< $@


build/python_dev.html: src/python_dev.html
	cp $< $@


build/matplotlib.html: src/matplotlib.html
	cp $< $@


build/matplotlib-sideload.html: src/matplotlib-sideload.html
	cp $< $@


build/test.html: src/test.html
	cp $< $@


build/renderedhtml.css: src/renderedhtml.less
	lessc $< $@


test: all
	pytest test/ -v


lint:
	flake8 src test tools pyodide_build benchmark
	clang-format -output-replacements-xml src/*.c src/*.h src/*.js | (! grep '<replacement ')


benchmark: all
	python benchmark/benchmark.py $(HOSTPYTHON) build/benchmarks.json
	python benchmark/plot_benchmark.py build/benchmarks.json build/benchmarks.png


clean:
	rm -fr root
	rm -fr build/*
	rm -fr src/*.bc
	make -C packages clean
	make -C six clean
	echo "The Emsdk, CPython and CLAPACK are not cleaned. cd into those directories to do so."


%.bc: %.c $(CPYTHONLIB) $(LZ4LIB)
	$(CC) -o $@ -c $< $(CFLAGS)


build/test.data: $(CPYTHONLIB)
	( \
	  cd $(CPYTHONLIB)/test; \
	  find -type d -name __pycache__ -prune -exec rm -rf {} \; \
	)
	( \
		cd build; \
		python $(FILEPACKAGER) test.data --lz4 --preload ../$(CPYTHONLIB)/test@/lib/python3.7/test --js-output=test.js --export-name=pyodide._module --exclude \*.wasm.pre --exclude __pycache__ \
  )
	uglifyjs build/test.js -o build/test.js


root/.built: \
		$(CPYTHONLIB) \
		$(SIX_LIBS) \
		src/sitecustomize.py \
		src/webbrowser.py \
		src/pyodide.py \
		remove_modules.txt
	rm -rf root
	mkdir -p root/lib
	cp -a $(CPYTHONLIB)/ root/lib
	cp $(SIX_LIBS) $(SITEPACKAGES)
	cp src/sitecustomize.py $(SITEPACKAGES)
	cp src/webbrowser.py root/lib/python$(PYMINOR)
	cp src/_testcapi.py	root/lib/python$(PYMINOR)
	cp src/pystone.py root/lib/python$(PYMINOR)
	cp src/pyodide.py root/lib/python$(PYMINOR)/site-packages
	( \
		cd root/lib/python$(PYMINOR); \
		rm -fr `cat ../../../remove_modules.txt`; \
		rm -fr test; \
		find . -name "*.wasm.pre" -type f -delete ; \
		find -type d -name __pycache__ -prune -exec rm -rf {} \; \
	)
	touch root/.built


ccache/emcc:
	mkdir -p $(PYODIDE_ROOT)/ccache ; \
	if hash ccache &>/dev/null; then \
    ln -s `which ccache` $(PYODIDE_ROOT)/ccache/emcc ; \
  else \
    ln -s emsdk/emsdk/emscripten/tag-1.38.12/emcc $(PYODIDE_ROOT)/ccache/emcc; \
  fi


ccache/em++:
	mkdir -p $(PYODIDE_ROOT)/ccache ; \
	if hash ccache &>/dev/null; then \
    ln -s `which ccache` $(PYODIDE_ROOT)/ccache/em++ ; \
  else \
    ln -s emsdk/emsdk/emscripten/tag-1.38.12/em++ $(PYODIDE_ROOT)/ccache/em++; \
  fi


$(CPYTHONLIB): emsdk/emsdk/.complete ccache/emcc ccache/em++
	make -C $(CPYTHONROOT)


$(LZ4LIB):
	make -C lz4


$(SIX_LIBS): $(CPYTHONLIB)
	make -C six


$(CLAPACK): $(CPYTHONLIB)
	make -C CLAPACK


build/packages.json: $(CPYTHONLIB) $(CLAPACK)
	make -C packages

emsdk/emsdk/.complete:
	make -C emsdk
