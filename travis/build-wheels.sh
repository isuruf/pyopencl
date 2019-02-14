#!/bin/bash
set -e -x

cd /io
mkdir -p deps
mkdir -p licenses
pushd deps

yum install -y git yum libxml2-devel xz

# Need ruby for ocl-icd
curl -L -O http://cache.ruby-lang.org/pub/ruby/2.1/ruby-2.1.2.tar.gz
tar -xf ruby-2.1.2.tar.gz
pushd ruby-2.1.2
./configure
make -j4
make install
popd

# OCL ICD loader
git clone --branch v2.2.12 https://github.com/OCL-dev/ocl-icd
pushd ocl-icd
curl -L -O https://raw.githubusercontent.com/conda-forge/ocl-icd-feedstock/master/recipe/install-headers.patch
git apply install-headers.patch
autoreconf -i
chmod +x configure
./configure --prefix=/usr
make -j4
make install
cp COPYING /io/licenses/OCL_ICD.COPYING
popd

# libhwloc for pocl
curl -L -O https://download.open-mpi.org/release/hwloc/v2.0/hwloc-2.0.3.tar.gz
tar -xf hwloc-2.0.3.tar.gz
pushd hwloc-2.0.3
./configure --disable-cairo --disable-opencl --disable-cuda --disable-nvml  --disable-gl --disable-libudev
make -j4
make install
cp COPYING /io/licenses/HWLOC.COPYING
popd

# newer cmake for LLVM
curl -L -O https://github.com/isuruf/isuruf.github.io/releases/download/v1.0/cmake-3.10.2-manylinux1_x86_64.tar.gz
pushd cmake
tar -xf ../cmake-3.10.2-manylinux1_x86_64.tar.gz
export PATH="`pwd`/bin:$PATH"

# LLVM for pocl
curl -L -O http://releases.llvm.org/6.0.1/llvm-6.0.1.src.tar.xz
unxz llvm-6.0.1.src.tar
tar -xf llvm-6.0.1.src.tar
pushd llvm-6.0.1.src
mkdir -p build
pushd build
cmake -DPYTHON_EXECUTABLE=/opt/python/cp37-cp37m/bin/python \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DLLVM_TARGETS_TO_BUILD=host \
      -DCMAKE_BUILD_TYPE=Release \
      -DLLVM_ENABLE_RTTI=ON \
      -DLLVM_INCLUDE_TESTS=OFF \
      -DLLVM_INCLUDE_GO_TESTS=OFF \
      -DLLVM_INCLUDE_UTILS=ON \
      -DLLVM_INCLUDE_DOCS=OFF \
      -DLLVM_INCLUDE_EXAMPLES=OFF \
      -DLLVM_ENABLE_TERMINFO=OFF \
      ..

make -j4
make install
popd
popd

curl -L -O http://releases.llvm.org/6.0.1/cfe-6.0.1.src.tar.xz
unxz cfe-6.0.1.src.tar
tar -xf cfe-6.0.1.src.tar
pushd cfe-6.0.1.src
mkdir -p build
pushd build
cmake \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_PREFIX_PATH=/usr/local \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_RTTI=ON \
  -DCLANG_INCLUDE_TESTS=OFF \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
..
make -j4
make install
popd
popd

popd

# Compile wheels
for PYBIN in /opt/python/*/bin; do
    "${PYBIN}/pip" install numpy pybind11 mako
    "${PYBIN}/pip" wheel /io/ -w wheelhouse/
done

# Bundle external shared libraries into the wheels
for whl in wheelhouse/pyopencl*.whl; do
    auditwheel repair "$whl" -w /io/wheelhouse/
done

# Bundle license files
/opt/python/cp37-cp37m/bin/pip install delocate
/opt/python/cp37-cp37m/bin/python /io/travis/fix-wheel.py /io/licenses/OCL_ICD.COPYING /io/licenses/HWLOC.COPYING

/opt/python/cp37-cp37m/bin/pip install twine
for WHEEL in /io/wheelhouse/pyopencl*.whl; do
    # dev
    # /opt/python/cp37-cp37m/bin/twine upload \
    #     --skip-existing \
    #     --repository-url https://test.pypi.org/legacy/ \
    #     -u "${TWINE_USERNAME}" -p "${TWINE_PASSWORD}" \
    #     "${WHEEL}"
    # prod
    /opt/python/cp37-cp37m/bin/twine upload \
        --skip-existing \
        -u "${TWINE_USERNAME}" -p "${TWINE_PASSWORD}" \
        "${WHEEL}"
done
