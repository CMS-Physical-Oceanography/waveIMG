% following Sutherland Melville 2013:
% 1) load intensity image I(x,y,t): may need to increase resolution from dx=0.7 & dy=0.8 
% 2) remove the "mean" intensity I0: foam should have a positive anomaly
% 3) using a roughly (6m x 7m) or (9px x 9px) window, estimate the window entropy
%    E = sum_i( p_i ln_2 (p_i) ), where p_i is the window's intensity-pdf
%    the bins should be something like: i = [0, 0.2, 0.4, 0.6, 0.8, 1.0] x max(I-I0).
%    this method of avoiding negative probability ignores foam-free water
%
% 1) load frame
videoDir = ['../../data/20130929/1100/'];
videoFile= ['20130929_112106_B314_00408CEBCECB_11.avi'];
frameNum = 15;
I  = load_vid_frame(videoDir,videoFile,frameNum);
%
%
% 2) remove mean
[foam_th,foam_pk,ob,opdf] = water_foam_threshold(I,1);
I0 = nanmean(I(:));
Ip = I-foam_th;
%
% 3) entropy filter
%    3.1) remove negative numbers (nan them)
Ip(Ip<0)=nan;
%    3.2) re-scale to [0 1]
Ipp = (Ip)/range(Ip(:));
%    3.3) pass to matlab's built in entropy filter
E   = entropyfilt(Ipp,ones(9,9));
     