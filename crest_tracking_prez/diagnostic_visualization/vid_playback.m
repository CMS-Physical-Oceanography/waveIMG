
% File path
videoFile = '/Volumes/RODSEX Video/BiasXMP4/BiasX_NorthTower_20221008_0830_matlab.mp4';

% Create video reader object
v = VideoReader(videoFile);

% Display video information
fprintf('Duration: %.2f seconds\n', v.Duration);
fprintf('Frame rate: %.2f fps\n', v.FrameRate);
fprintf('Resolution: %d x %d\n', v.Width, v.Height);

% Play video

implay(videoFile);

% figure('Name', 'RODSEX Video', 'NumberTitle', 'off');
% ax = axes;
% 
% while hasFrame(v)
%     frame = readFrame(v);
%     imshow(frame, 'Parent', ax);
%     title(ax, sprintf('Time: %.1f s', v.CurrentTime));
%     drawnow;
% end