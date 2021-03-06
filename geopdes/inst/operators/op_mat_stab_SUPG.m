% OP_MAT_STAB_SUPG: assemble the stabilization matrix A = [a(i,j)],
%   a(i,j) =  tau_h * { - ( mu * lapl(u_j) , vel \cdot grad v_i )
%			- ( grad (mu) \cdot grad (u_j), vel \cdot grad (v_i) )
%			+ ( vel \cdot grad u_j, vel \cdot grad v_i ) }
%
% The current version only works for the scalar case.
%
%   mat = op_mat_stab_SUPG (spu, spv, msh, mu, grad_mu, vel);
%   [rows, cols, values] = op_mat_stab_SUPG (spu, spv, msh, mu, grad_mu, vel)
%
% INPUT:
%
%   spu:   structure representing the space of trial functions (see sp_scalar/sp_evaluate_col)
%   spv:   structure representing the space of test functions (see sp_scalar/sp_evaluate_col)
%   msh:   structure containing the domain partition and the quadrature rule (see msh_cartesian/msh_evaluate_col)
%   mu:    diffusion coefficient evaluated at the quadrature points
%   grad_mu: gradient of the diffusion coefficiet, evaluated at the quadrature points
%   vel: advection coefficient( vectorial function ), evaluated at the quadrature points
%
% OUTPUT:
%
%   mat:    assembled advection matrix
%   rows:   row indices of the nonzero entries
%   cols:   column indices of the nonzero entries
%   values: values of the nonzero entries
% 
% Copyright (C) 2009, 2010 Carlo de Falco
% Copyright (C) 2011, 2014, 2017 Rafael Vazquez
% Copyright (C) 2013, Anna Tagliabue
%
%    This program is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.

%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see <http://www.gnu.org/licenses/>.

function varargout = op_mat_stab_SUPG (spu, spv, msh, coeff_mu, grad_coeff, vel)

  gradu = reshape (spu.shape_function_gradients, spu.ncomp, [], ...
                   msh.nqn, spu.nsh_max, msh.nel);
  gradv = reshape (spv.shape_function_gradients, spv.ncomp, [], ...
		   msh.nqn, spv.nsh_max, msh.nel);

  ndir = size (gradu, 2);

  laplu = reshape (spu.shape_function_laplacians, spu.ncomp, msh.nqn, spu.nsh_max, msh.nel);

  rows = zeros (msh.nel * spu.nsh_max * spv.nsh_max, 1);
  cols = zeros (msh.nel * spu.nsh_max * spv.nsh_max, 1);
  values = zeros (msh.nel * spu.nsh_max * spv.nsh_max, 1);

  coeff_mu = reshape (coeff_mu, 1, msh.nqn, msh.nel);
  p = max ([spu.degree(:); spv.degree(:)]);

  jacdet_weights = msh.jacdet .* msh.quad_weights;
  
  ncounter = 0;
  for iel = 1:msh.nel
    if (all (msh.jacdet(:, iel)))
      vel_iel = reshape (vel(:, :, iel), ndir, msh.nqn);

% compute parameters relative to the stabilization coefficient
      h_iel = msh.element_size(iel);
      max_coeff = max (abs (coeff_mu(1, :, iel)));
      [max_vel,ind] = max (sqrt (sum (vel_iel.^2., 1)));
% Length in the direction of the velocity. This could be improved.
      h_iel = h_iel / max (abs (vel_iel(:,ind)) / max_vel);

      Pe = max_vel * h_iel / (2. * max_coeff);
      tau = h_iel / (2. * max_vel) * min (1., Pe / ( 3. * p * p ));

      jacdet_weights_tau = reshape (tau * jacdet_weights(:,iel), [1, msh.nqn, 1, 1]);
      jacdet_weights_vel = reshape (bsxfun (@times, jacdet_weights_tau, vel_iel), [ndir, msh.nqn, 1, 1]);

      %~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      gradu_iel = reshape (gradu(:,:,:,1:spu.nsh(iel),iel), spu.ncomp*ndir, msh.nqn, 1, spu.nsh(iel));
      laplu_iel = reshape (laplu(:,:,1:spu.nsh(iel),iel), spu.ncomp, msh.nqn, 1, spu.nsh(iel));
      gradv_iel = reshape (gradv(:,:,:,1:spv.nsh(iel),iel), spv.ncomp*ndir, msh.nqn, spv.nsh(iel), 1);

      %~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      gradv_dot_vel_times_jw = sum (bsxfun (@times, jacdet_weights_vel, gradv_iel), 1);

      laplu_times_mu = bsxfun (@times, coeff_mu(:, :, iel), laplu_iel);
      gradu_dot_gradmu = sum (bsxfun (@times, grad_coeff(:, :, iel), gradu_iel), 1);
      gradu_dot_vel = sum (bsxfun (@times, vel_iel, gradu_iel), 1);

      %~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      aux_sum = laplu_times_mu + gradu_dot_gradmu + gradu_dot_vel;
      aux_val = bsxfun (@times, gradv_dot_vel_times_jw, aux_sum);

      values(ncounter+(1:spu.nsh(iel)*spv.nsh(iel))) = reshape (sum (sum (aux_val, 2), 1), spv.nsh(iel), spu.nsh(iel));
      
      [rows_loc, cols_loc] = ndgrid (spv.connectivity(:,iel), spu.connectivity(:,iel));
      rows(ncounter+(1:spu.nsh(iel)*spv.nsh(iel))) = rows_loc;
      cols(ncounter+(1:spu.nsh(iel)*spv.nsh(iel))) = cols_loc;
      ncounter = ncounter + spu.nsh(iel)*spv.nsh(iel);

    else
      warning ('geopdes:jacdet_zero_at_quad_node', 'op_mat_stab_SUPG: singular map in element number %d', iel)
    end
  end

  if (nargout == 1 || nargout == 0)
    varargout{1} = sparse (rows(1:ncounter), cols(1:ncounter), ...
                           values(1:ncounter), spv.ndof, spu.ndof);
  elseif (nargout == 3)
    varargout{1} = rows(1:ncounter);
    varargout{2} = cols(1:ncounter);
    varargout{3} = values(1:ncounter);
  else
    error ('op_mat_stab_SUPG: wrong number of output arguments')
  end

end

