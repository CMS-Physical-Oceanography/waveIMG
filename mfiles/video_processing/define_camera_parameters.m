function [info,icp,beta0] = define_camera_parameters()
% subdirectories

% video info
info.format = 'avi';
info.freq   = 2.5;
% grid info
info.X_res = 0.2;
info.Y_res = 0.2000
info.X_min = 75
info.X_max = 250
info.Y_min = 590
info.Y_max = 1000
% other info
info.Al_bar = 10;
info.Cs_bar = 10
info.X_gap = []
info.Y_gap = []
info.vel_bnd = [-2 2]
info.wndw = 20
info.stp = 10
info.minvar = 100
info.maxskew = 2
info.minent = 6



% camera intrinsic parameters
icp.PixelFormat = 'RGB';
icp.BitDepth =  24
icp.FrameRate =  5
icp.NU = 2048
icp.NV = 1536
icp.c0U = 1.0903e+03
icp.c0V = 797.5000
icp.fx = 1.9518e+03
icp.fy = 1953
icp.d1 = -0.3826
icp.d2 = 0.2136
icp.d3 = -0.0815
icp.t1 = 5.0000e-05
icp.t2 = 3.0690e-04
icp.ac = 8.5330e-04
icp.r = [0 1.0000e-03 0.0020 0.0030 0.0040 0.0050 0.0060 0.0070 0.0080 0.0090 0.0100 0.0110 0.0120  ]
icp.fr = [1 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 1.0000 0.9999  ]
icp.x = [-1.5000 -1.4000 -1.3000 -1.2000 -1.1000 -1 -0.9000 -0.8000 -0.7000 -0.6000 -0.5000 -0.4000  ]
icp.y = [-1.3000 -1.2000 -1.1000 -1 -0.9000 -0.8000 -0.7000 -0.6000 -0.5000 -0.4000 -0.3000 -0.2000  ]

icp = makeRadialDistortion(icp);
icp = makeTangentialDistortion(icp);
%icp.dx = [27×31 double]
%icp.dy = [27×31 double]

% extrinsic camera parameters
beta0 = [35.0911  585.0288   42.4419   72.1536    0.1974   44.8175];