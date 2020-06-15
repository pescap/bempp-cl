#include "bempp_base_types.h"
#include "bempp_helpers.h"
#include "bempp_spaces.h"
#include "kernels.h"

__kernel __attribute__((vec_type_hint(REALTYPEVEC))) void kernel_function(
	 __global REALTYPE* grid,
	 __global int* neighborIndices,
	 __global int* neighborIndexptr,
	 __global REALTYPE* localPoints,
	 __global REALTYPE* coefficients,
	 __global REALTYPE* result,
	 __global REALTYPE* kernelParameters,
	 uint nelements
	 )
{
  size_t gid = get_global_id(0);

  int indexStart = neighborIndexptr[gid];
  int indexEnd = neighborIndexptr[1 + gid];

  int nIndices = indexEnd - indexStart;
  int nChunks = (NPOINTS * nIndices) / VEC_LENGTH;

  REALTYPE globalSourcePoints[3 * MAX_POINTS];
  REALTYPE localCoefficients[MAX_POINTS][2];
  REALTYPE3 targetCorners[3];
  REALTYPE3 sourceCorners[3];
  REALTYPE3 globalPoint;
  REALTYPEVEC sourceVecPoint[3];
  REALTYPEVEC diffVec[3];
  REALTYPE diff[3];
  REALTYPEVEC distVec;
  REALTYPEVEC rdistVec;
  REALTYPEVEC expvalVec[2];
  REALTYPEVEC factorVec[2];
  REALTYPEVEC tmpVec[2];
  REALTYPE dist;
  REALTYPE rdist;
  REALTYPE factor[2];
  REALTYPE expval[2];
  REALTYPE tmp[2];
  REALTYPE3 targetPoint;
  REALTYPE2 point;
  REALTYPEVEC coeffsVec[2];
  REALTYPEVEC resultVec[4][2];
  REALTYPE resultSingle[4][2];
  
  getCorners(grid, gid, targetCorners);

  // First compute global points

  int count = 0;
  for (int i = 0; i < nIndices; ++i){
      int elem = neighborIndices[i + indexStart];
      getCorners(grid, elem, sourceCorners);
      for (int localIndex = 0; localIndex < NPOINTS; ++localIndex)
      	  {
		point = (REALTYPE2)(localPoints[2 * localIndex],
		                    localPoints[2 * localIndex + 1]);
		globalPoint = getGlobalPoint(sourceCorners, &point);
		globalSourcePoints[3 * count] = globalPoint.x;
		globalSourcePoints[3 * count + 1] = globalPoint.y;
		globalSourcePoints[3 * count + 2] = globalPoint.z;
		localCoefficients[count][0] = coefficients[2 * (NPOINTS * elem + localIndex) + 0];
		localCoefficients[count][1] = coefficients[2 * (NPOINTS * elem + localIndex) + 1];
		count += 1;
	}
   }


  for (int targetIndex = 0; targetIndex < NPOINTS; targetIndex++)
    {

      for (int i = 0; i < 4; i++){
	resultVec[i][0] = M_ZERO;
	resultSingle[i][0] = M_ZERO;
	resultVec[i][1] = M_ZERO;
	resultSingle[i][1] = M_ZERO;
      }

      point = (REALTYPE2)(localPoints[2 * targetIndex],
      		    localPoints[2 * targetIndex + 1]);

      targetPoint = getGlobalPoint(targetCorners, &point);

      for (int chunkIndex = 0; chunkIndex < nChunks; chunkIndex++){
	// Fill chunk
	for (int vecIndex = 0; vecIndex < VEC_LENGTH; vecIndex++){
	  VEC_ELEMENT(sourceVecPoint[0], vecIndex) = globalSourcePoints[3 * (VEC_LENGTH * chunkIndex + vecIndex) + 0];
	  VEC_ELEMENT(sourceVecPoint[1], vecIndex) = globalSourcePoints[3 * (VEC_LENGTH * chunkIndex + vecIndex) + 1];
	  VEC_ELEMENT(sourceVecPoint[2], vecIndex) = globalSourcePoints[3 * (VEC_LENGTH * chunkIndex + vecIndex) + 2];
	  VEC_ELEMENT(coeffsVec[0],vecIndex) = localCoefficients[VEC_LENGTH * chunkIndex + vecIndex][0];
	  VEC_ELEMENT(coeffsVec[1], vecIndex) = localCoefficients[VEC_LENGTH * chunkIndex + vecIndex][1];
	}

	diffVec[0] = targetPoint.x - sourceVecPoint[0];
	diffVec[1] = targetPoint.y - sourceVecPoint[1];
	diffVec[2] = targetPoint.z - sourceVecPoint[2];

	
	distVec = sqrt(diffVec[0] * diffVec[0] + diffVec[1] * diffVec[1] + diffVec[2] * diffVec[2]);
	rdistVec = M_ONE / distVec;
	// Check for zero dist case
	for (int vecIndex = 0; vecIndex < VEC_LENGTH; vecIndex++){
	  if ((VEC_ELEMENT(diffVec[0], vecIndex) == M_ZERO) && (VEC_ELEMENT(diffVec[1], vecIndex) == M_ZERO) && (VEC_ELEMENT(diffVec[2], vecIndex) == M_ZERO))
	    VEC_ELEMENT(rdistVec, vecIndex) = M_ZERO;
	}

	expvalVec[0] = cos(kernel_parameters[0] * distVec);
	expValVec[1] = sin(kernel_parameters[0] * distVec);
	if (kernel_parameters[1] != M_ZERO){
	  expvalVec[0] *= exp(-kernel_parameters[1] * distVec);
	  expvalVec[1] *= exp(-kernel_parameters[1] * distVec);
	}
	
	resultVec[0][0] += CMP_MULT_REAL(expvalVec, coeffsVec) * rdistVec * M_INV_4PI;
	resultVec[0][1] += CMP_MULT_IMAG(expvalVec, coeffsVec) * rdistVec * M_INV_4PI;

	factorVec[0] = -M_ONE;
	factorVec[1] = kernel_parameters[0] * distVec;
	if (kernel_parameters[1] != M_ZERO)
	    factorVec[0] -= kernel_parameters[1] * distVec;

	tmpVec[0] = CMP_MULT_REAL(factorVec, resultVec[0]) * rdistVec * rdistVec;
	tmpVec[1] = CMP_MULT_IMAG(factorVec, resultVec[0]) * rdistVec * rdistVec;
	
	resultVec[1][0] += tmpVec[0] * diffVec[0];
	resultVec[1][1] += tmpVec[1] * diffVec[0];
	resultVec[2][0] += tmpVec[0] * diffVec[1];
	resultVec[2][1] += tmpVec[1] * diffVec[1];
	resultVec[3][0] += tmpVec[0] * diffVec[2];
	resultVec[2][1] += tmpVec[1] * diffVec[2];
	
      }

      // Now process the remainder scalar points
      for (int remainderIndex = nChunks * VEC_LENGTH; remainderIndex < NPOINTS * nIndices; remainderIndex++)
	{
	  diff[0] = targetPoint.x - globalSourcePoints[3 * remainderIndex + 0];
	  diff[1] = targetPoint.y - globalSourcePoints[3 * remainderIndex + 1];
	  diff[2] = targetPoint.z - globalSourcePoints[3 * remainderIndex + 2];

	  dist = sqrt(diff[0] * diff[0] + diff[1] * diff[1] + diff[2] * diff[2]);
	  rdist = M_ONE / dist;
	  if ((diff[0] == M_ZERO) && (diff[1] == M_ZERO) && (diff[2] == M_ZERO))
	    rdist = M_ZERO;

	  expval[0] = cos(kernel_parameters[0] * dist);
	  expVal[1] = sin(kernel_parameters[0] * dist);
	  if (kernel_parameters[1] != M_ZERO){
	    expval[0] *= exp(-kernel_parameters[1] * dist);
	    expval[1] *= exp(-kernel_parameters[1] * dist);
	  }
	
	  resultSingle[0][0] += CMP_MULT_REAL(expval, localCoefficients[remainderIndex]) * rdist * M_INV_4PI;
	  resultSingle[0][1] += CMP_MULT_IMAG(expval, localCoefficients[remainderIndex]) * rdist * M_INV_4PI;

	  factor[0] = -M_ONE;
	  factor[1] = kernel_parameters[0] * dist;
	  if (kernel_parameters[1] != M_ZERO)
	    factor[0] -= kernel_parameters[1] * dist;

	  tmp[0] = CMP_MULT_REAL(factor, resultSingle[0]) * rdist * rdist;
	  tmp[1] = CMP_MULT_IMAG(factor, resultSingle[0]) * rdist * rdist;
	
	  resultSingle[1][0] += tmp[0] * diff[0];
	  resultSingle[1][1] += tmp[1] * diff[0];
	  resultSingle[2][0] += tmp[0] * diff[1];
	  resultSingle[2][1] += tmp[1] * diff[1];
	  resultSingle[3][0] += tmp[0] * diff[2];
	  resultSingle[2][1] += tmp[1] * diff[2];



	}
      
      result[2 * (4 * (NPOINTS * gid + targetIndex) + 0) + 0] = resultSingle[0][0];
      result[2 * (4 * (NPOINTS * gid + targetIndex) + 0) + 1] = resultSingle[0][1];

      result[2 * (4 * (NPOINTS * gid + targetIndex) + 1) + 0] = resultSingle[1][0];
      result[2 * (4 * (NPOINTS * gid + targetIndex) + 1) + 1] = resultSingle[1][1];

      result[2 * (4 * (NPOINTS * gid + targetIndex) + 2) + 0] = resultSingle[2][0];
      result[2 * (4 * (NPOINTS * gid + targetIndex) + 2) + 1] = resultSingle[2][1];

      result[2 * (4 * (NPOINTS * gid + targetIndex) + 3) + 0] = resultSingle[3][0];
      result[2 * (4 * (NPOINTS * gid + targetIndex) + 3) + 1] = resultSingle[3][1];
      
      
      for (int vecIndex = 0; vecIndex < VEC_LENGTH; vecIndex++){
        result[2 * (4 * (NPOINTS * gid + targetIndex) + 0) + 0] += VEC_ELEMENT(resultVec[0][0], vecIndex);
	result[2 * (4 * (NPOINTS * gid + targetIndex) + 0) + 1] += VEC_ELEMENT(resultVec[0][1], vecIndex);

        result[2 * (4 * (NPOINTS * gid + targetIndex) + 1) + 0] += VEC_ELEMENT(resultVec[1][0], vecIndex);
	result[2 * (4 * (NPOINTS * gid + targetIndex) + 1) + 1] += VEC_ELEMENT(resultVec[1][1], vecIndex);

        result[2 * (4 * (NPOINTS * gid + targetIndex) + 2) + 0] += VEC_ELEMENT(resultVec[2][0], vecIndex);
	result[2 * (4 * (NPOINTS * gid + targetIndex) + 2) + 1] += VEC_ELEMENT(resultVec[2][1], vecIndex);

        result[2 * (4 * (NPOINTS * gid + targetIndex) + 3) + 0] += VEC_ELEMENT(resultVec[3][0], vecIndex);
	result[2 * (4 * (NPOINTS * gid + targetIndex) + 3) + 1] += VEC_ELEMENT(resultVec[3][1], vecIndex);
	
      }
      
    }

}      
      


