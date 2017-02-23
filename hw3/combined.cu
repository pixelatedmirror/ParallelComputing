//#include <omp.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <sys/mman.h>
#include <sys/stat.h>
#include <iostream>
#include <fcntl.h>
#include <cmath>

#include "globals.h"
#include "fns.h"

using namespace std;



float *x, *y, *z;



int main(int argc, char* argv[]){
  char* &filename = argv[1];
  vector<const char*> lineAddrs;
  int ndex = 0;//omp_get_max_threads();
  if(argc>=3) ndex=atoi(argv[2]);
  struct stat st;
  stat(filename, &st);
  size_t filesize = st.st_size;
  int fd = open(filename,O_RDONLY,0);
  void* file = mmap(NULL,  filesize, PROT_READ, MAP_PRIVATE | MAP_POPULATE, fd, 0);
  const char* input = (const char*) file;
  int lines=0;
  lineAddrs.push_back(input);
  for(int i=0;i<filesize;i++){
    if(input[i]=='\n'){
      lines++;
      lineAddrs.push_back(input+i+1);
    }
  }
  fillCPU();
  fillGPU();
  fillGPUTiled();
  munmap(file, filesize);
  calcCPU();
  calcGPU();
  calcGPUTiled();
  return 0;
}


void fillCPU(){
  x=(float*) malloc((size_t) lines*sizeof(float));
  y=(float*) malloc((size_t) lines*sizeof(float));
  z=(float*) malloc((size_t) lines*sizeof(float));
  for(int i=0;i<lines;i++){
    const char *a,*b,*c;
    char temp[30];
    a=lineAddrs[i];
    b=strpbrk(strpbrk(a," \t"),"-0123456789");
    c=strpbrk(strpbrk(b," \t"),"-0123456789");
    x[i]=atof(a);
    y[i]=atof(b);
    z[i]=atof(c);
    if(!(i%1000)) cout<<i<<endl;
  }
}

void fillGPU(){
  cudaMallocManaged(&x,   (size_t) lines*sizeof(float));
  cudaMallocManaged(&y,   (size_t) lines*sizeof(float));
  cudaMallocManaged(&z,   (size_t) lines*sizeof(float));
  cudaMallocManaged(&res, (size_t) lines*sizeof(float));
  for(int i=0;i<lines;i++){
    const char *a,*b,*c;
    a=lineAddrs[i];
    b=strpbrk(strpbrk(a," \t"),"-0123456789");
    c=strpbrk(strpbrk(b," \t"),"-0123456789");
    x[i]=atof(a);
    y[i]=atof(b);
    z[i]=atof(c);
    if(!(i%1000)) cout<<i<<endl;
  }
}

void fillGPUTiled(){
  float *valuesA = new float[lines*3];
  float *valuesB = new float[lines*3];
  float *results = new float[lines*lines];
  cudaMallocManaged(&res, (int) (lines*sizeof(float)));
  for(int i=0;i<lines;i++){
    const char *a,*b,*c;
    a=lineAddrs[i];
    b=strpbrk(strpbrk(a," \t"),"-0123456789");
    c=strpbrk(strpbrk(b," \t"),"-0123456789");
    valuesA[i]         = valuesB[3*i]   = atof(a);
    valuesA[lines+i]   = valuesB[3*i+1] = atof(b);
    valuesA[2*lines+i] = valuesB[3*i+2] = atof(c);
    if(!(i%1000)) cout<<i<<endl;
  }
  for(int i=0;i<3*lines;i++){
    if(isnan(valuesA[i])) cout<<"NAN A "<<i<<endl;
    if(isnan(valuesB[i])) cout<<"NAN A "<<i<<endl;
  }
}

void calcCPU(){
  double total=0.0f;
#pragma omp parallel for reduction(+:total)
  for(int i=0;i<lines;i++){
    double subtotal=0.0f, dx, dy, dz;
    for(int j=0;j<lines;j++){
      if(i==j) continue;
      dx=x[i]-x[j];
      dx=y[i]-y[j];
      dx=z[i]-z[j];
      double d=sqrt(dx*dx+dy*dy+dz*dz);
      if(d==0.0f) continue;
      subtotal+=1/d;
    }
    total+=subtotal;
  }
  cout<<total<<endl;
}

void calcGPU(){
  const size_t block_size = 256;
  size_t grid_size = (lines + block_size -1)/ block_size;
  cout<<"Sending to GPU"<<endl;
  // launch the kernel
  calcGravity<<<grid_size, block_size>>>(lines);
 
  cudaDeviceSynchronize();
  cout<<"Summing"<<endl;
  double total=0.0f;
  for(int i=0;i<lines;i++){
    total+=res[i];
  }
  cout<<total<<endl;
}

void calcGPUTiled(){
   Matrix A, B, C;
  A.width=3;
  A.height=lines;
  A.stride=lines;
  A.elements=valuesA;
  B.width=lines;
  B.height=3;
  B.stride=3;
  B.elements=valuesB;
  C.width=lines;
  C.height=lines;
  C.stride=lines;
  C.elements=results;
  MatMul(A,B,C);
  cudaDeviceSynchronize();
  cout<<"Summing"<<endl;
  double total=0.0f;
  for(int i=0;i<lines*lines;i++){
    total+=(double)results[i];
    if(i%100000000 == 0) cout<<total<<endl;
    if(isnan(results[i])) cout<<"NAN: "<<i<<endl;
    //if(i%(lines*1000) == 0) cout<<endl;
  }
  cout<<total<<endl;
}