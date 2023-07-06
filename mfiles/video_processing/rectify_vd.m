function [ocean,oceanSum,oceanX,oceanY,infoOCM] = rectify_vd(workingDir,importDir,expID)

[infoOCM] = getOCMparams(expID);  %get analysis parameters
%infoOCM.tag = tag;
infoOCM.workingDir = workingDir;
infoOCM.importDir = importDir;
infoOCM.expID = expID;

fprintf('\n processing video directory %s \n',importDir)

%% PREPARE IMAGES
%[icp, beta0] = getCameraParams(infoOCM.expID); %import camera info
[info, icp, beta0] = define_camera_parameters()
keyboard
[U, V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);  %find U, V coordinates

imp_source = dir(strcat(infoOCM.importDir, filesep,'*.', infoOCM.imp_format)); %find all videos in source folder

%check for bad files
dot = 1;
while dot < length(imp_source)
    if strcmp(imp_source(dot).name(1:2),'._')
        imp_source(dot) = [];
    end
    dot = dot+1;
end

imp_name = {imp_source.name}';  %cell array of video names
imp_read = strcat({imp_source.folder},filesep,{imp_source.name})';  %string of each video location

time_source = dir(strcat(infoOCM.importDir, filesep,'*.', 'xml')); %find all videos in source folder
time_read = strcat({time_source.folder},filesep,{time_source.name})';  %string of each video location

vd = VideoReader(imp_read{1});

oceanRaw = double(rgb2gray(read(vd,1)));

[oceanX, oceanY] = meshgrid(infoOCM.X_min:infoOCM.X_res:infoOCM.X_max,infoOCM.Y_min:infoOCM.Y_res:infoOCM.Y_max);   %define image grid
[Uint, Vint] = getUVfromXYZ(oceanX, oceanY, zeros(size(oceanX)), icp, beta0);

oceanGrid = interp2(U, V, oceanRaw, Uint, Vint, 'linear', nan);

%load NAVD water level
[z,tz] = getWaterLevel(expID);

%% IMPORT AND ANALYZE
%load and grid images into ocean array
for j = 1:length(imp_read)
    fprintf('processing video number %d of %d \n',j,length(imp_read))
    %generate time
    fid = fopen(time_read{j});
    l = fgetl(fid);
    fclose(fid);
    startTimeStr = regexp(l, '(?<=<StartTime>).*(?=</StartTime>)', 'match');
    startTime = datetime(startTimeStr{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSS''Z''', 'TimeZone', 'UTC', 'Format', 'yyyy-MM-dd HH:mm:ss.SSSS');

    vd = VideoReader(imp_read{j});
    vdHz = vd.FrameRate;
    vdDr = vd.Duration;

    samp = round(vdHz/infoOCM.ocm_freq);
    frms = 1:samp:vd.NumFrames;
    M = length(frms);

    %added to try to include z coordinate
    z_stp =  interp1(tz,z,startTime+seconds(vdDr/2));
    [Ustp, Vstp] = getUVfromXYZ(oceanX, oceanY, z_stp*ones(size(oceanX)), icp, beta0);

    %load in each image and interpolate to grid
    ocean = NaN(size(oceanGrid,1),size(oceanGrid,2),M); %preallocate ocean array
    for ii = 1:M %loop through image set
        oceanRaw = double(rgb2gray(read(vd,frms(ii))));    %read in image
        ocean(:,:,ii) = interp2(U, V, oceanRaw, Ustp, Vstp, 'linear', nan);
        keyboard
    end
    %sum images into composite
    oceanSum = sum(ocean,3);

    %save results
    save(strcat(infoOCM.workingDir,filesep,'rawData_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'ocean','oceanSum','oceanX','oceanY','-v7.3')
    save(strcat(infoOCM.workingDir,filesep,'timex_OCM_',infoOCM.tag,'_',imp_name{j}(1:end-4),'.mat'),'oceanSum','oceanX','oceanY')
end

end