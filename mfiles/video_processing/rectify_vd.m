function [ocean,oceanSum,oceanX,oceanY,info] = rectify_vd(workingDir,importDir,expID)

%[infoOCM] = getOCMparams(expID);  %get analysis parameters
%infoOCM.tag = tag;
[info, icp, beta0] = define_camera_parameters();
info.workingDir = workingDir;
info.importDir = importDir;
info.expID = expID;

fprintf('\n processing video directory %s \n',importDir)

%% PREPARE IMAGES
%[icp, beta0] = getCameraParams(infoOCM.expID); %import camera info

[U, V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);  %find U, V coordinates

 %find all videos in source folder

%check for bad files
%dot = 1;
%while dot < length(imp_source)
    %if strcmp(imp_source(dot).name(1:2),'._')
        %imp_source(dot) = [];
    %end
    %dot = dot+1;
%end

%imp_name = {workingDir.name}';  %cell array of video names
%imp_read = strcat({workingDir.folder},filesep,{imp_source.name})';  %string of each video location

time_source = [workingDir, filesep, importDir(1:end-4),'.xml']; %find all videos in source folder
time_read = strcat(workingDir, filesep, importDir(1:end-4));  %string of each video location

vd = VideoReader(workingDir);

oceanRaw = double(rgb2gray(read(vd,1)));

[oceanX, oceanY] = meshgrid(info.X_min:info.X_res:info.X_max,info.Y_min:info.Y_res:info.Y_max);   %define image grid
[Uint, Vint] = getUVfromXYZ(oceanX, oceanY, zeros(size(oceanX)), icp, beta0);

oceanGrid = interp2(U, V, oceanRaw, Uint, Vint, 'linear', nan);

%load NAVD water level
[z,tz] = getWaterLevel(expID);

%% IMPORT AND ANALYZE
%load and grid images into ocean array
%{
for j = 1:length(importDir)
    fprintf('processing video number %d of %d \n',j,length(importDir))
    %generate time
    fid = fopen(time_read);
    l = fgetl(fid);
    fclose(fid);
    startTimeStr = regexp(l, '(?<=<StartTime>).*(?=</StartTime>)', 'match');
    keyboard
    startTime = datetime(startTimeStr{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss.SSSS');
%}

    vd = VideoReader(workingDir);
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
    %save(strcat(infoOCM.workingDir,filesep,'rawData_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'ocean','oceanSum','oceanX','oceanY','-v7.3')
    %save(strcat(infoOCM.workingDir,filesep,'timex_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'oceanSum','oceanX','oceanY')
end

