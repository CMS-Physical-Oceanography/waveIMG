function app = load_video(app)
%
% USAGE: app = load_video(app)
%
% function reads video, grid, and camera parameters;
% loads the current video, rectifies first frame-only. 

[info, icp, beta0] = define_camera_parameters();

app.info = info;
app.icp  = icp;
app.beta0= app.beta0;

videoDir = [app.SelectCurrentDirectory.Value, filesep];
videoFile= app.SelectCurrentFilename.Value;

fprintf('\n loading video %s \n',app.SelectCurrentFilename.Value)

% prepare image (U,V) coordinates for rectification
[U, V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);

timeFile = [videoDir, filesep, videoFile(1:end-4),'.xml']; %find all videos in source folder

app.vid = VideoReader(videoDir);

% get first frame
frameNum = app.CurrentFrameNum.Value
keyboard
oceanRaw = double(rgb2gray(read(vd,1)));

[oceanX, oceanY] = meshgrid(info.X_min:info.X_res:info.X_max,info.Y_min:info.Y_res:info.Y_max);   %define image grid
app.X = oceanX;
app.Y = oceanY;

[Uint, Vint] = getUVfromXYZ(oceanX, oceanY, zeros(size(oceanX)), icp, beta0);

oceanGrid = interp2(U, V, oceanRaw, Uint, Vint, 'linear', nan);

%load NAVD water level
[z,tz] = getWaterLevel(expID);

%% IMPORT AND ANALYZE
%load and grid images into ocean array
%{
for j = 1:length(videoFile)
    fprintf('processing video number %d of %d \n',j,length(videoFile))
    %generate time
    fid = fopen(time_read);
    l = fgetl(fid);
    fclose(fid);
    startTimeStr = regexp(l, '(?<=<StartTime>).*(?=</StartTime>)', 'match');
    keyboard
    startTime = datetime(startTimeStr{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss.SSSS');
%}

    vd = VideoReader(videoDir);
    vdHz = vd.FrameRate;
    vdDr = vd.Duration;

    samp = round(vdHz/info.freq);
    frms = 1:samp:vd.NumFrames;
    M = length(frms);

    %added to try to include z coordinate
    z_stp =  0; %interp1(tz,z,startTime+seconds(vdDr/2));
    [Ustp, Vstp] = getUVfromXYZ(oceanX, oceanY, z_stp*ones(size(oceanX)), icp, beta0);

    %load in each image and interpolate to grid
    ocean = NaN(size(oceanGrid,1),size(oceanGrid,2),M); %preallocate ocean array
    for ii = 1:M %loop through image set
        oceanRaw = double(rgb2gray(read(vd,frms(ii))));    %read in image
        ocean(:,:,ii) = interp2(U, V, oceanRaw, Ustp, Vstp, 'linear', nan);
        
    end
    %sum images into composite
    oceanSum = sum(ocean,3);

    %save results
    %save(strcat(infoOCM.videoDir,filesep,'rawData_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'ocean','oceanSum','oceanX','oceanY','-v7.3')
    %save(strcat(infoOCM.videoDir,filesep,'timex_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'oceanSum','oceanX','oceanY')
end

